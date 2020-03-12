function [V, xyt]  = load_timeseries(V, F, xyt, path_input)
    
    %% filenames
    Dataset_dir = ['dataset ' F(5).FileName];
    meteo_ec_csv = F(6).FileName;
    vegetation_retrieved_csv  = F(7).FileName;

    t_column = F(strcmp({F.FileID}, 't')).FileName;
    year_column = F(strcmp({F.FileID}, 'year')).FileName;

    %% read berkeley format dataset
    df = readtable(fullfile(path_input, Dataset_dir, meteo_ec_csv), ...
        'TreatAsEmpty', {'.','NA','N/A'});
%     df = standardizeMissing(df, -9999); > 2013a
    t_ = df.(t_column);
    t_(t_ == -9999) = nan;
    
    if all(t_ <= 367)  % doy is provided
        %assert(~isempty(year_column), 'Please, provide year in your .csv')
        if(isempty(year_column)), year_n = 2020; 
        else
        % then we calculate ts for you
            year_n = df.(year_column);
        end
        t_ = datestr(datenum(year_n, 0, t_), 'yyyymmddHHMMSS.FFF');
    end
    
    t_ = io.timestamp2datetime(t_);
    xyt.startDOY = io.timestamp2datetime(xyt.startDOY);
    xyt.endDOY = io.timestamp2datetime(xyt.endDOY);
    year_n = year(t_);
    
    %% filtering
    time_i = (t_ >= xyt.startDOY) & (t_ <= xyt.endDOY);   
    df_sub = df(time_i, :);

    %% time 
    t_ = t_(time_i);
    xyt.t = t_;
    xyt.year = year_n(time_i);  % for legacy and doy to date convertion

    %% optional interpolation_csv file
    interpolatable_cols = {};
    if ~isempty(vegetation_retrieved_csv)
        df_int = readtable(fullfile(path_input, Dataset_dir, vegetation_retrieved_csv), ...
            'TreatAsEmpty', {'.','NA','N/A'});
        t_int = df_int.(t_column);
        if any(t_int > 367)
            t_int = io.timestamp2datetime(t_int);
        end
        assert(min(t_) >= min(t_int) & max(t_) <= max(t_int), '`interpolation_csv` timestamp is outside `ec_file_berkeley` timestamp')
        interpolatable_cols = df_int.Properties.VariableNames;
    end

    %% make correspondence: F.FileID : index in V struct
    i_empty = cellfun(@isempty, {F.FileName});
    f_ids = {F(~i_empty).FileID};
    f_names = {F(~i_empty).FileName};
    v_names = {V.Name};
    [~, iF, iV] = intersect(f_ids, v_names, 'stable');
    
    %% read fields that were provided (f_ids)
    for i = 1:length(iF)  % == length(iV)
        fi_i = iF(i);
        vi_i = iV(i);
        col_name = char(f_names(fi_i));
        % TODO replace missing by default?
        if any(strcmp(interpolatable_cols, col_name))
            V(vi_i).Val = interp1(t_int, df_int.(col_name), t_);
        else
            tmp = df_sub.(col_name);
            tmp(tmp == -9999) = nan;
            if all(isnan(tmp))
                warning('%s has NaNs along all timestamp. Calculations may fail', col_name)
            end
            V(vi_i).Val = tmp;
        end
    end

    %% special cases
    %% tts calculation
    if ~any(strcmp(f_ids, 'tts'))  % tts wasn't read
        vi_tts = strcmp(v_names, 'tts');
        if isdatetime(t_)
            get_doy = @(x) juliandate(x) - juliandate(datetime(year(x), 1, 0));
            t_ = get_doy(t_);
        end
        DOY_  = floor(t_);
        time_ = 24*(t_-DOY_);
        ttsR  = equations.calczenithangle(DOY_,time_ - xyt.timezn ,0,0,xyt.LON,xyt.LAT);     %sun zenith angle in rad
        V(vi_tts).Val = min(85, ttsR / pi * 180);     
    end

    %% ea calculation
    if ~any(strcmp(f_ids, 'ea')) && any(strcmp(f_ids, 'Ta'))  % ea wasn't read but Ta was
        ta = V(strcmp(v_names, 'Ta')).Val;
        es = equations.satvap(ta);
        vi_ea = strcmp(v_names, 'ea');
        rh_column = F(strcmp({F.FileID}, 'RH')).FileName;
        vpd_column = F(strcmp({F.FileID}, 'VPD')).FileName;
        if ~isempty(rh_column)
            rh = df_sub.(rh_column);
            rh(rh == -9999) = nan;
            if any(rh > 10)
                rh = rh / 100;    % rh from [0 100] to [0 1]
                warning('converted relative hudimity from [0 100] to [0 1]')
            end
            ea = es .* rh;
            warning('calculated ea from Ta and RH')
            V(vi_ea).Val = ea;
        elseif ~isempty(vpd_column)
            vpd = df_sub.(vpd_column);
            vpd(vpd == -9999) = nan;
            ea = es - vpd;
            warning('calculated ea from Ta and VPD')
            if any(ea < 0)
                warning('some ea < 0, is your VPD in hPa?')
            end
            V(vi_ea).Val = ea;
        end 
    end

    %% units convertion
    %% p
    if any(strcmp(f_ids, 'p'))
        vi_p = strcmp(v_names, 'p');
        p = V(vi_p).Val;
        if any(p < 500)
            p = p * 10;
            warning('converted air pressure from kPa to hPa')
        end
        V(vi_p).Val = p;
    end

    %% smc
    if any(strcmp(f_ids, 'SMC'))
        vi_smc = strcmp(v_names, 'SMC');
        smc = V(vi_smc).Val;
        if any(smc > 1)
            smc = smc / 100;  % SMC from [0 100] to [0 1]
            warning('converted soil moisture content from from [0 100] to [0 1]')
        end     
        V(vi_smc).Val = smc;
    end
end
