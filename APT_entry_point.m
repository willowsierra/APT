function APT_entry_point(task_id, job_id, fun, clusterID)
    global APT_PARAMS JOB_INFO;
    APT_params();           
    
    clusterID = str2double(clusterID);
    drive = get_drive_path(clusterID);
    args_dir = fullfile(drive, APT_PARAMS.temp_dir, task_id, 'args');
    res_dir  = fullfile(drive, APT_PARAMS.temp_dir, task_id, 'res');
    sh_dir   = fullfile(drive, APT_PARAMS.temp_dir, task_id, 'scripts');
    
    res_file_tmp = fullfile(res_dir, sprintf('res_%s.mat', job_id));
    res_file     = fullfile(res_dir, sprintf('res%s.mat', job_id));        
    
    stop_file = fullfile(sh_dir, 'stop');    
    
    try     
        % Mark job as started
        % Write job ID to allow deletion from master 
        if ~isdeployed 
            pid = APT_getpid();
            [s, host] = system('echo -n $HOSTNAME');            
        else
            [s, pid] = system('echo $JOB_ID');
            pid = str2double(pid);
            host = APT_PARAMS.cluster_IP{clusterID};            
        end        
        fid = fopen(fullfile(sh_dir, sprintf('started%s', job_id)), 'w');
        fprintf(fid, '%d@%s ', pid, host);
        fclose(fid);                      

        load(fullfile(sh_dir, 'params.mat'), 'params');
        
        % Set number of threads, by default SingleCompThread is activated
        if params.NSlots > 1
            warning off;
            maxNumCompThreads(params.NSlots);
            warning on;        
        end
        
        % Set path for local execution
        if ~isdeployed        
            for i = 1:length(params.user_paths)
                addpath(params.user_paths{i});
            end                                 
        end                           
        
        % Set job info
        JOB_INFO.cluster_id = clusterID;
        JOB_INFO.inside_APT = 1;
                
        fun = regexprep(fun, '\\(["|*|\\])', '$1');
          
        %======================================================================      

        load(fullfile(args_dir, 'common.mat'), 'common', 'tobecomb_args');       
        load(fullfile(args_dir, sprintf('args%s.mat', job_id)), 'args', 'argsID', 'jobIDs');   
        ninst = length(jobIDs);
        parallel_args = cell(1, length(argsID));
        [index pos] = sort(-argsID, 'ascend'); 
        parallel_args(pos(index>0)) = common;
        clear common;                         

        %If a loaded class call javaaddpath, global variable are cleared
        %from memory. We call APT_params again:
        if ~exist('APT_PARAMS', 'var')
            global APT_PARAMS JOB_INFO;
            APT_params();  
        end
                                                                    
        fprintf('Log file for task %s, job %s\n', task_id, job_id); 
        
        t1 = clock;    
        res = cell(ninst, 1);
                   
        E = []; % no error for now
        errorJobID = 0;
        for i = 1 : ninst            
            JOB_INFO.job_id   = jobIDs(i);
            JOB_INFO.user_dir = fullfile('/local', APT_PARAMS.login, APT_PARAMS.loc_dir, sprintf('%s_%d', task_id, JOB_INFO.job_id));
            [s,m] = mkdir(JOB_INFO.user_dir);              
            
            % Check if USER did CTRL+C
            fid = fopen(stop_file, 'r');    
            stopped = str2double(fread(fid, 1, '*char'));
            fclose(fid);            
            if stopped == 2
                fprintf('Catched stop signal, exiting... (put 0 in %s to avoid this)\n', stop_file);
                return;
            end
            
            RandStream.setGlobalStream(RandStream('mt19937ar', 'Seed', jobIDs(i)));
            
            fprintf('*** Launching ''%s'' for parameter set #%d ***\n', fun, jobIDs(i));           
            
            [index pos] = sort(argsID, 'ascend'); 
            if ~params.CombineArgs
                if ~isempty(args)
                    parallel_args(pos(index>0)) = args(:, i);            
                end
            else                
                pos = pos(index>0);      
                for j = 1 : size(args, 1)                    
                    parallel_args{pos(j)} = tobecomb_args{j}{args{j, i}};
                end
            end
            
            % run user function
            try
                if params.WaitEnd
                    res{i} = execute_function(fun, parallel_args, params.nargout);
                else
                    res{i} = execute_function(fun, parallel_args, params.funnargout); % Compute all outputs as we do not know how many are needed
                end
            catch tmpE
                fprintf('Error for parameter set #%d: %s\n', jobIDs(i), tmpE.message);
                print_error(tmpE);
                if isempty(E)
                    E = tmpE;
                    errorJobID = jobIDs(i);
                end
            end
            
            % remove local temporary files
            try
                rmdir(JOB_INFO.user_dir, 's');
            catch 
            end
        end
        
        if ~isempty(E)
            fprintf('Error for parameter set #%d: %s\n', errorJobID, E.message);
            print_error(E);
            
            save(res_file_tmp, 'E');
        else
            E = [];
            res = cat(1, res{:});
            t2 = clock;
            time = etime(t2, t1);  
            [memUsedMb mem] = APT_memory_usage();
            info = whos('res');
            if info.bytes >= 2000000000
                save(res_file_tmp, 'E', 'res', 'time', 'mem', '-v7.3');
            else
                save(res_file_tmp, 'E', 'res', 'time', 'mem');                    
            end
        end
    catch E        
        fprintf('Critical error: %s\n', E.message);
        print_error(E);
        
        save(res_file_tmp, 'E');                 
        
        try
            rmdir(JOB_INFO.user_dir, 's');
        catch 
        end        
    end  
    
    while(1)
        try
            [s, r] = system(sprintf('mv %s %s', res_file_tmp, res_file));
            % Sometimes the movefile has no effect
            if exist(res_file, 'file') == 2
                break;
            end
        catch
        end
        pause(1);
    end
           
    exit;    
end

%==========================================================================
function res = execute_function(fun, args, funnargout)
    if fun(1) == '@'
        myfun = 'APT_f';
        eval(sprintf('%s = %s;', myfun, fun));
        fun = myfun;
    end
    n_args = length(args);
    if n_args == 0
        argsstr = [];
    elseif n_args == 1 
        argsstr = 'args{1}';
    else
        argsstr = sprintf('args{1}%s', sprintf(', args{%d}', 2:n_args));
    end        
        
    if funnargout == 0
        eval(sprintf('%s(%s);', fun, argsstr));
        res = [];
    else
        out = sprintf('o%d ', 1:funnargout);
        eval(sprintf('[%s] = %s(%s); res = {%s};', out, fun, argsstr, out));
    end
end

%==========================================================================
function exp_dirs = expand_dirs(dirs)
    n_dirs = length(dirs);
    exp_dirs = cell(1, n_dirs);
    for i = 1 : n_dirs
        if ~isdir(dirs{i})
            [d f] = fileparts(dirs{i});
            if f == '*'
                if ~isempty(dir(fullfile(d, '*.m'))) || ~isempty(dir(fullfile(d, ['*.' mexext])))
                    exp_dirs{i} = {d};
                end
            else
                exp_dirs{i} = {dirs{i}};
            end
        else
            d = dir(dirs{i});
            d = {d([d(:).isdir]).name};
            keep = true(length(d), 1);
            for j = 1 : length(d)
                if ~isempty(find(strcmp({'.' '..'}, d{j}), 1))
                    keep(j) = 0;
                else
                    d{j} = fullfile(dirs{i}, d{j});
                end                
            end
            d = d(keep);
            if ~isempty(d)
                exp_dirs{i} = expand_dirs(d);
            end
            if ~isempty(dir(fullfile(dirs{i}, '*.m'))) || ~isempty(dir(fullfile(dirs{i}, ['*.' mexext])))
                exp_dirs{i} = [{dirs{i}} exp_dirs{i}];
            end
        end                
    end
    exp_dirs = cat(2, exp_dirs{:});
end

%==========================================================================
function path = get_drive_path(host)    
    global APT_PARAMS;   
    if nargin < 1
        [s, h] = system('hostname');
        host = find(strcmpi(h, APT_PARAMS.cluster_IP), 1);
        if isempty(host)
            host = 0;
        end
    elseif host == 0
        [s, h] = system('hostname');
        if strcmp(h(1:4), 'node')
            host = 1; % actualy we don't care if it is meleze or sequoia
        end
    end
    
    for i = 1 : size(APT_PARAMS.drives, 1)
        if strcmp(APT_PARAMS.temp_drive, APT_PARAMS.drives{i, 1})            
            path = APT_PARAMS.drives{i, 2 + host};
            return;
        end
    end
    error('Unknown drive %s.\n', APT_PARAMS.temp_drive);    
end

%==========================================================================
function print_error(E)
    for k=1:length(E.stack)
        fprintf('In ==> %s at %d\n', E.stack(k).name, E.stack(k).line);      
    end
end
