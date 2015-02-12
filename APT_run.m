function varargout = APT_run(task, varargin)      
    global APT_PARAMS JOB_INFO;
    if isempty(APT_PARAMS)
        APT_params();
    end                 
    
    %======================================================================
    
    params = struct( ...
                    'ClusterID', 0, ...
                    'CombineArgs', 0, ...
                    'GroupBy', 0, ...
                    'HostName', {APT_PARAMS.host_name}, ...
                    'KeepTmp', [], ...                    
                    'Libs', {{}}, ...
                    'Memory', 0, ...
                    'NJobs', 0, ... 
                    'NoJVM', 1, ...                    
                    'NoLoad', 0, ...                    
                    'NSlots', 1, ...                    
                    'ResumeType', 0, ...                    
                    'ShellVar', {{}}, ...
                    'TimeOut', 0, ...
                    'UseCluster', 1, ...                    
                    'Verbose', APT_PARAMS.verbose, ...
                    'WaitEnd', 1, ...     
                    'Coffee', 0 ...  
                   );
                
    %======================================================================
    % Checking for uncleaned temporary files
    root = fullfile(APT_get_drive(), APT_PARAMS.temp_dir);
    files = dir(root);
        
    removeAfterNDays = 7;
    for i = 1 : length(files)
        if files(i).isdir && isempty(find(strcmp(files(i).name, {'.' '..'})))
            [state f] = get_state(fullfile(root, files(i).name));
            f = dir(f);
            if isempty(state) || (state >= 2 && now - f.datenum >= removeAfterNDays) % after 'removeAfterNDays' days
                APT_remove();
                break;
            end
        end
    end    
    
    %======================================================================
    
    % MOD: params, parallel_args
    if ischar(task) 
        i = 1;
        while i <= length(varargin) && (iscell(varargin{i}) || isnumeric(varargin{i}) || isstruct(varargin{i})) 
            if isnumeric(varargin{i})
                if length(varargin{i}) ~= numel(varargin{i})
                    n_args = size(varargin{i}, 1);
                    args = cell(n_args, 1);
                    for j = 1 : n_args
                        args{j} = varargin{i}(j, :);
                    end  
                    varargin{i} = args;              
                else
                    varargin{i} = num2cell(varargin{i});
                end
            end
            if isstruct(varargin{i})
                c = cell(1, length(varargin{i}));
                for k = 1 : length(varargin{i})
                    c{k} = varargin{i}(k);                    
                end
                varargin{i} = c;
            end
            if isempty(varargin{i})
                error('Argument %d is empty.', i+1);
            end
            if length(size(varargin{i})) >= 3
                error('Argument %d should be at most 2-dimensional.', i+1);
            end
            if length(varargin{i}) ~= numel(varargin{i})
                n_args = size(varargin{i}, 1);
                args = cell(n_args, 1);
                for j = 1 : n_args
                    args{j} = varargin{i}(j, :);
                end  
                varargin{i} = args;
            end                      
            i = i + 1;
        end        
        parallel_args = varargin(1:(i-1));
        varargin = varargin(i:end);
    end               
    
    if mod(size(varargin, 2), 2)
        error('Wrong input arguments : the ''property'' ''value'' scheme is not respected.\nIf may be also due to the fact you don''t pass constant parameters in a one element cell.');
    end    
    args = reshape(varargin, 2, size(varargin, 2) / 2);
    for i = 1 : size(args, 2)
        if ischar(args{1, i})
            if isfield(params, args{1, i})
                params.(args{1, i}) = args{2, i};
            else
                error('Unknown optionnal parameter name : %s', args{1, i});
            end
        else
            error('Expecting a cell or a string for argument %d.', 1 + length(parallel_args) + i);
        end
    end     
      
    %======================================================================
    
    if params.Coffee
        makeCoffe();
        return;
    end
    
    params.nargout = nargout;   
    
    for i = 1 : length(params.ShellVar)
        if numel(params.ShellVar{i}) ~= 2
            error('ShellVar should be a cell of pairs {variable value}');
        end
    end
        
    if ischar(task)     
        if params.CombineArgs
            nargs = length(parallel_args);
            params.combine_dims = zeros(1, nargs);
            for i = 1 : nargs
                params.combine_dims(i) = length(parallel_args{i});
            end
            ninst = prod(params.combine_dims);           
        else
            ninst = 1;
            arg_ref = 0;
            for i = 1 : length(parallel_args)
                if length(parallel_args{i}) > 1
                    if ninst == 1
                        ninst = length(parallel_args{i});
                        arg_ref = i;
                    elseif length(parallel_args{i}) ~= ninst
                        error('According to argument %d there are %d tasks but argument %d has %d elements.\nIf you want to combine each possible arguments please set the ''CombineArgs'' option to 1.', arg_ref+1, ninst, i+1, length(parallel_args{i}));
                    end                
                end
            end
        end   
        params.ninst = ninst;
        
        if strcmp(task(end-1:end), '.m')
            task = task(1:end-2);
        end
        if task(1) == '@'
            if ~params.WaitEnd
                if nargout >= 2
                    error('APT_run does not support anonymous function with more than one output argument in non-blocking mode.');
                end
                funnargout = 1;
            else
                funnargout = nargout;
            end            
        else
            if strcmp(which(task), '') 
                error('Unable to find file ''%s.m''.', task);
            end
            try
                funnargout = nargout(task);
            catch
                funnargout = nargout;
            end                
        end          
        
        if params.NoLoad && nargout > 1
            error('Too many output arguments. When used with NoLoad == 1, APT_run outputs tID where ''tID'' is the task ID.');
        end
        
        if ~params.WaitEnd
            if nargout > 2
                error('Too many output arguments. When used with WaitEnd == 0, APT_run outputs [tID done] where ''tID'' is the task ID and ''done'' is non zero if the task is finished.');
            end
        else            
            if funnargout >= 0 && nargout > funnargout
                error('The function ''%s'', has not enough output arguments.', task);
            end
        end
        params.funnargout = funnargout;
        
        params.UseCluster = params.UseCluster & ~APT_PARAMS.force_local;
        if params.GroupBy
            if ~params.UseCluster
                warning('Parameter ''GroupBy'' was ignored: it cannot be used for local computation. You should use ''NJobs'' instead.');
                params.GroupBy = 0;
            else
                if params.NJobs
                    error('Parameters ''GroupBy'' and ''NJobs'' are mutually exclusive. Please specify one or the other.');
                else
                    params.NJobs = max(round(params.ninst / params.GroupBy), 1);
                end
            end
        end   
        
        if ~params.NJobs
            if params.UseCluster
                params.NJobs = params.ninst;
            else
                if APT_PARAMS.numcores
                    params.NJobs = APT_PARAMS.numcores;
                else                    
                    [~, s] = system('egrep -c ''^processor'' /proc/cpuinfo'); 
                    params.NJobs = str2double(s);
                end
            end        
        end        
        params.NJobs = min(params.ninst, params.NJobs);   
        
        if params.NSlots < 1
                params.NSlots = 1;
        end        
    end
    
    drive = APT_get_drive();
    if params.UseCluster   
        if exist(fullfile(drive, APT_PARAMS.temp_dir, APT_PARAMS.exec_name), 'file') ~= 2
            error('Please compile your matlab code using APT_compile() before running it.');
        end                          
        if isfield(JOB_INFO, 'inside_APT') && JOB_INFO.inside_APT == 1 && JOB_INFO.cluster_id ~= 0
            if ischar(task)
                stack = dbstack();
                error('In %s line %d : You cannot use APT inside a function launched on the cluster (global variable JOB_INFO is non-empty).', stack(2).name, stack(2).line);
            else
                error('You cannot resume a task from a job running in parallel.');
            end
        end            
        if APT_PARAMS.cluster_id ~= 0 && params.ClusterID == 0;
            params.ClusterID = APT_PARAMS.cluster_id;            
        end               
        if params.ClusterID < 0 || params.ClusterID > length(APT_PARAMS.cluster_IP)
            error('Unknown cluster ID ''%d'' : ClusterID should be 1 for meleze or 2 for sequoia (also check APT_params.m)', params.ClusterID);
        end        
    end    
            
    if ischar(task)            
        params.fun = task;
        params.pause_time = 10;
        
        params = check_comp_args(params);
        
        params.task_id = open_parallel_task(parallel_args, params);   
        resume = 0;   
        
        if params.UseCluster
            if params.ClusterID == 0
                params.ClusterID = choose_cluster(params);
            end    
            write_submit_scripts(params);
        end
        
        if isempty(params.KeepTmp)
            if params.NoLoad
                params.KeepTmp = 1;
            else
                params.KeepTmp = 0;
            end
        end
        
        if params.Verbose >= 0
            if params.UseCluster
                loc = APT_PARAMS.cluster_IP{params.ClusterID};                
            else
                loc = 'local machine';
            end
            fprintf('Running ''%s'' on %s.\n', task, loc);
        end             
    elseif isscalar(task)
        if params.ResumeType ~= 0 && params.ResumeType ~= 1
            error('ResumeType should be 0 or 1.');
        end
        
        if ~isempty(params.ShellVar)
            error('You cannot change the shell variable when resuming a task.');
        end
        
        new_params = params;
        try
            load(fullfile(drive, APT_PARAMS.temp_dir, num2str(task), 'scripts', 'params.mat'), 'params');
        catch 
            error('Unable to load task parameters. Check the task ID and make sure the task has not already finished.');
        end        
        old_params = params;        
        params = new_params; 
        params.ninst = old_params.ninst;
        params.funnargout = old_params.funnargout;      
        params.fun = old_params.fun;
        params.pause_time = old_params.pause_time;
        params.task_id = num2str(task);     
        params.NJobs = old_params.NJobs;
        params.GroupBy = old_params.GroupBy;
        params.CombineArgs = old_params.CombineArgs;
        if isfield(old_params, 'combine_dims')
            params.combine_dims = old_params.combine_dims;
        end
        params.ShellVar = old_params.ShellVar;
        params.KeepTmp = (isempty(params.KeepTmp) && (params.NoLoad || ~isempty(old_params.KeepTmp) && old_params.KeepTmp)) || (~isempty(params.KeepTmp) && params.KeepTmp);        
        if params.Memory == 0
            params.Memory = old_params.Memory;
        end
        resume = 1;
        
        params = check_comp_args(params);
        
        if params.ClusterID == 0 && params.UseCluster
            params.ClusterID = choose_cluster(params);            
        end     
        write_submit_scripts(params);
        
        if params.Verbose > 0
            if params.UseCluster
                loc = APT_PARAMS.cluster_IP{params.ClusterID};
            else
                loc = 'local machine';                
            end
            fprintf('Resuming task %d (''%s'') on %s\n', task, params.fun, loc);            
        end
    else
        error('First parameter should be a function name (string) or a task ID (scalar).');
    end    
          
    %======================================================================
            
    jobs_info = repmat(struct('launched', 0, 'started', 0, 'finished', 0, 'error', 0, 'res', [], 'time', [], 'mem', []), params.NJobs, 1);
    if resume
        sh_dir = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts');
        if params.ResumeType == 1
            delete(fullfile(sh_dir, 'launched*'));  
            delete(fullfile(sh_dir, 'started*'));
        end
        jobs_info = update_jobs_info(params, jobs_info, 1);
        if params.ResumeType == 1
            waiting = find(~[jobs_info(:).finished]);
        else
            waiting = find([jobs_info(:).error] | (~[jobs_info(:).finished] & ~[jobs_info(:).launched]));
        end
        for i = 1 : length(jobs_info)
            jobs_info(i).error = 0;
        end
    else
        waiting = find(~[jobs_info(:).finished]);
    end
    
    if params.Verbose == 1
        fprintf('Launching jobs... ');
    end       
    launch_jobs(params, waiting);
    waiting = find(~[jobs_info(:).finished]);
    if params.Verbose == 1
        fprintf('done\n');
    end    
    
    if ~params.WaitEnd
        if nargout >= 1
            varargout{1} = str2double(params.task_id);
        end
        if nargout >= 2
            if ~isempty(find([jobs_info(:).error], 1))
                varargout{2} = 2;
            elseif isempty(waiting)
                varargout{2} = 1;
            else
                varargout{2} = 0;
            end
        end
        return;
    end
    
    tic;
    last_n_finish = -Inf;
    while ~isempty(waiting)
        if params.TimeOut > 0 && toc > params.TimeOut
            fprintf('TIMEOUT !\n');
            return;
        end
        
        [s,key] = system(sprintf('read -n1 -s -t%d key; echo $key', params.pause_time));                       
        if (~isempty(key) && (key(1) == 'q' || key(1) == 'Q')) || s == 130
            t = input('Kill running jobs, [y]es/[n]o/[c]ancel ?\n', 's');                    
            if strcmpi(t, 'y') 
                kill_jobs(params);
            end
            
            if strcmpi(t, 'y') || strcmpi(t, 'n') 
                set_state(params.task_id, 2);
                stop_file = fullfile(APT_get_drive(), APT_PARAMS.temp_dir, params.task_id, 'scripts', 'stop');
                fid = fopen(stop_file, 'w');      
                fprintf(fid, '2');             
                fclose(fid);
                error('Operation terminated by user.');
            end
        end            
        
        [jobs_info new_errors] = update_jobs_info(params, jobs_info);
        
        if params.Verbose >= 1 && ~isempty(new_errors)
            for i = new_errors
                msg = make_error_msg(jobs_info(i).res);
                fprintf('*** Job %d crashed: ***\n', i);
                fprintf(msg);
                fprintf('\n');
            end
        end

        % Check for threads which may have had problem for reading the MCR at starting.        
        failed = find(~[jobs_info(:).finished] & ([jobs_info(:).launched] > max(5*params.pause_time, 100)) & ~[jobs_info(:).started]);
        if ~isempty(failed) 
            if params.Verbose >= 2
                fprintf('Relaunching tasks: %s\n', sprintf(' %d', failed));         
            end            
            sh_dir = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts');
            for i = failed
                delete(fullfile(sh_dir, sprintf('launched%d', i)));
                jobs_info(i).launched = 0;
            end
            launch_jobs(params, failed);              
        end            
        
        waiting = find(~[jobs_info(:).finished]);
        if params.Verbose >= 1            
            n_finish = length(find([jobs_info(:).finished]));            
            if last_n_finish ~= n_finish
                last_n_finish = n_finish;
                d = datestr(clock);
                mean_time = [jobs_info(:).time];
                if isempty(mean_time)
                    mean_time = 'unknown';
                else
                    mean_time = [num2str(round(mean(mean_time))) 's'];
                end
                max_mem = [jobs_info(:).mem];            
                if isempty(max_mem)
                    max_mem = 'unknown';
                else
                    max_mem = round(max(max_mem)) / 1000;
                    if params.Memory == 0
                        max_mem = sprintf('%.1fGb', max_mem);
                    else
                        if max_mem < params.Memory * 0.7 / 1000;
                            fprintf('[%s] Task %s: ===============> PLEASE LOWER MEMORY REQUEST <===============\n', d, params.task_id);
                        end                    
                        max_mem = sprintf('%.1fGb/%.1fGb', max_mem, params.Memory / 1000);                    
                    end
                end    
                n_error = length(find([jobs_info(:).error]));
                fprintf('[%s] Task %s: %d/%d jobs finished (%d errors), Avg. time: %s, Max. mem: %s\n', d, params.task_id, n_finish, params.NJobs, n_error, mean_time, max_mem);
                if n_error
                    fprintf('Crashed jobs IDs: %s\n', sprintf(' %d', find([jobs_info(:).error]))); 
                end                  
            end
        end   
    end    
    
    errors = find([jobs_info(:).error]);
    if isempty(errors)
        set_state(params.task_id, 3);
        if ~params.NoLoad
            result = cat(1, jobs_info(:).res);          
            if nargout                        
                for i = 1 : nargout        
                    if params.CombineArgs
                        varargout{i} = reshape(result(:, i), params.combine_dims);             
                    else
                        varargout{i} = result(:, i);
                    end
                end
            end 
            if ~params.KeepTmp
                rm_tmp(params); 
            end
        else
            if nargout >= 1
                varargout{1} = str2double(params.task_id);
            end
        end
    else        
        set_state(params.task_id, 2);
        msg = sprintf('The following job(s) crashed:%s\n', sprintf(' %d', errors));
        msg = [msg sprintf('Please consult each report file in %s for job specific error(s).\n', fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'logs'))];
        msg = [msg sprintf('Below is an exemple of the encountred error for job %d:\n\n', errors(1))];
        msg = [msg make_error_msg(jobs_info(errors(1)).res)];       
        error(msg);                
    end
end

%======================================================================
function params = check_comp_args(params)
    global APT_PARAMS;
    
    if params.UseCluster
        root = fullfile(APT_get_drive(), APT_PARAMS.temp_dir);
        fid = fopen(fullfile(root, [APT_PARAMS.exec_name '.inf']), 'rt');
        if fid >= 0 % Compatibility with 1.2
            compInf = fread(fid, Inf, '*char')';
            flags = regexp(compInf, 'flags="[^;]*"', 'match');
            flags = flags{1}(8 : (end-1));
            if params.NSlots ~= 1 && ~isempty(strfind(flags, 'singleCompThread'))
                warning('The code was compiled with ''singleCompThread'' option: NSlots was set to ''1''.\nCompile using "APT_compile(''SingleThread'', 0)" to avoid this.');
                params.NSlots = 1;
            end        
            if params.NoJVM == 0 && ~isempty(strfind(flags, 'nojvm'))
                warning('The code was compiled with ''NoJVM'' option: NoJVM was set to ''1''.\nCompile using "APT_compile(''NoJVM'', 0)" to avoid this.');
                params.NoJVM = 1;
            end
            funsnames = regexp(compInf, 'funs="[^;]*"', 'match');
            funsnames = funsnames{1}(7 : (end-1));
            funs = regexp(funsnames, '\w*', 'match');
            if ~isempty(funs)   % it was compiled for particular functions only
                if ~strcmp(params.fun, funs)
                    error('The code was compiled for the following function(s) only: %s', funsnames);
                end
            end
            fclose(fid);
        end
    end
end
    
%======================================================================
function rm_tmp(params, confirm)
    global APT_PARAMS;
    
    if params.KeepTmp
        return;
    end
    
    path = fullfile(APT_get_drive(), APT_PARAMS.temp_dir, params.task_id);
    if nargin >= 2 && confirm
        fprintf('\n\n');
        t = input(sprintf('Remove temporary files at %s, [y]/n ?\n', path), 's');
        if strcmp(t, 'n')
            fprintf('Temporary files kept.\n');
            return;
        else
            fprintf('Temporary files deleted.\n');
        end
    end        
          
    try
        [s, m] = system(sprintf('rm -rf %s', path));        
    catch ME
    end    
end

%======================================================================
function task_id = open_parallel_task(parallel_args, params)
	global APT_PARAMS;
    drive = APT_get_drive();
    [s,m] = mkdir(drive, APT_PARAMS.temp_dir);
    
    task_id = generate_key();
    while isdir(fullfile(drive, APT_PARAMS.temp_dir, task_id))
        task_id = generate_key();
    end
    
    if params.Verbose >= 0
        fprintf('Task ID = %s, #jobs = %d\n', task_id, params.NJobs);
    end
    
    if params.Verbose >= 1
        fprintf('Writing arguments on disk...\n');
    end
    
    task_dir = fullfile(drive, APT_PARAMS.temp_dir, task_id);
    [s,m] = mkdir(task_dir);
    
    params.user_paths = find_user_paths();    
    
    args_dir = fullfile(task_dir, 'args');
    sh_dir   = fullfile(task_dir, 'scripts');
    [s,m] = mkdir(args_dir);
    [s,m] = mkdir(sh_dir);
    [s,m] = mkdir(fullfile(task_dir, 'res'));    
    [s,m] = mkdir(fullfile(task_dir, 'logs'));
    save(fullfile(sh_dir, 'params.mat'), 'params');               
    
    n_args = length(parallel_args);
    is_common = false(1, n_args);
    argsID = zeros(1, n_args);
    n_common = 0;
    for i = 1 : n_args
        if length(parallel_args{i}) == 1
            is_common(i) = 1; 
            n_common = n_common + 1;
            argsID(i) = -n_common;
            parallel_args{i} = parallel_args{i}{1};
        else
            argsID(i) = i - n_common;
            if ~params.CombineArgs
                parallel_args{i} = reshape(parallel_args{i}, 1, params.ninst);
            else
                parallel_args{i} = reshape(parallel_args{i}, 1, length(parallel_args{i}));
            end
        end
    end
    common = parallel_args(is_common);
    if ~params.CombineArgs
        parallel_args = cat(1, parallel_args{~is_common});   
        tobecomb_args = [];
    else
        parallel_args = parallel_args(~is_common);
        tobecomb_args = parallel_args;        
        combine = 1:length(parallel_args{1});
        for i = 2 : length(parallel_args)            
            newcombine = kron(1:length(parallel_args{i}), ones(1, size(combine, 2)));
            combine = repmat(combine, 1, length(parallel_args{i}));            
            combine = [combine; newcombine];
        end 
        for i = 1 : length(parallel_args)    
            parallel_args{i} = num2cell(combine(i, :));
        end
        parallel_args = cat(1, parallel_args{:});   
    end
    s = whos('common');
    if s.bytes > 2000000000
        % WARNING : Processing big cells with -v7.3 takes infinite time.
        save(fullfile(args_dir, 'common.mat'), 'common', 'tobecomb_args', '-v7.3');
    else
        save(fullfile(args_dir, 'common.mat'), 'common', 'tobecomb_args');
    end
       
    index = [0 round(params.ninst * (1 : params.NJobs) / params.NJobs)];  % we know that params.ninst >= params.NJobs
    for i = 1 : params.NJobs
        jobIDs = (index(i)+1) : index(i+1);         
        if ~isempty(parallel_args)
            args = parallel_args(:, jobIDs);      
        else
            args = [];
        end
        s = whos('args');
        if s.bytes > 2000000000
            % WARNING : Processing big cells with -v7.3 takes infinite time.
            save(fullfile(args_dir, sprintf('args%d.mat',i)), 'args', 'argsID', 'jobIDs', '-v7.3');       
        else
            save(fullfile(args_dir, sprintf('args%d.mat',i)), 'args', 'argsID', 'jobIDs');       
        end        
    end
end

%==========================================================================
function write_submit_scripts(params)
    global APT_PARAMS;

    if params.fun(1) == '@'
        jobname = 'anonymous_fun';        
    else
        jobname = params.fun;
    end    

    cluster_arch = APT_PARAMS.cluster_arch{params.ClusterID};
    if ~params.Memory
        params.Memory = ceil(cluster_arch(3) * 1000 / cluster_arch(2));
    end       
    swap_allowed = floor(max(0, (cluster_arch(4) - 2) * 1000 / cluster_arch(2)) * params.NSlots);  
    
    if params.Verbose >= 2
        fprintf('Job memory set to %0.1fGb + %0.1fGb additional. NSlots = %d\n', params.Memory/1000, swap_allowed/1000, max(1, params.NSlots));
    end    
    
    cluster_drive = APT_get_drive([], params.ClusterID);
    log_dir = fullfile(cluster_drive, APT_PARAMS.temp_dir, params.task_id, 'logs');
    sh_dir  = fullfile(APT_get_drive(), APT_PARAMS.temp_dir, params.task_id, 'scripts');        
    
    libs = reshape(APT_PARAMS.default_libs, 1, numel(APT_PARAMS.default_libs));
    libs = [libs reshape(params.Libs, 1, numel(params.Libs))];  
    libs = make_path(libs);

    runner = fullfile(cluster_drive, APT_PARAMS.temp_dir, ['run_' APT_PARAMS.exec_name '.sh ']);
    funname = regexprep(regexprep(params.fun, '%', '%%'), '("|*|\\)', '\\$1');
    
    MCR = [];
    for i = 1 : size(APT_PARAMS.MCR, 1)
        if strfind(matlabroot, APT_PARAMS.MCR{i, 1})
            MCR = APT_PARAMS.MCR{i, 2};
            break;
        end
    end
    if isempty(MCR)
        v = sprintf(', %s', APT_PARAMS.MCR{2 : end, 1});
        v = [APT_PARAMS.MCR{1, 1} v];
        error('Please change your matlab version, the MCR for this version is not supported.\nSupported versions are: %s.', v);        
    end
    
    for i = 1 : params.NJobs
        fid = fopen(fullfile(sh_dir, sprintf('submit%d.pbs', i)), 'w');
        fprintf(fid,'#$ -l mem_req=%dm\n', params.Memory);
        fprintf(fid,'#$ -l h_vmem=%dm\n', params.Memory + swap_allowed);
        if params.NSlots > 1
            fprintf(fid,'#$ -pe serial %d\n', params.NSlots);    
        end
        if ~isempty(params.HostName)
            if iscell(params.HostName)
                if length(params.HostName) == 1
                    fprintf(fid,'#$ -l hostname="%s"\n', params.HostName{1});
                else
                    fprintf(fid,'#$ -l hostname="%s%s"\n', params.HostName{1}, sprintf('|%s', params.HostName{2:end}));
                end
            else
                fprintf(fid,'#$ -l hostname=%s\n', params.HostName);
            end
        end
        fprintf(fid,'#$ -e %s \n', log_dir);
        fprintf(fid,'#$ -o %s \n', log_dir);
        fprintf(fid,'#$ -N _%d_%s \n', i, jobname);
        for k = 1 : length(params.ShellVar)
            fprintf(fid,'%s=%s\n', params.ShellVar{k}{1}, params.ShellVar{k}{2});
            fprintf(fid,'export %s\n', params.ShellVar{k}{1});
        end
        fprintf(fid,'sh %s "%s" "%s" "%s" "%d" "%s" "%d" > %s \n', runner, MCR, libs, params.task_id, i, funname, params.ClusterID, fullfile(log_dir, sprintf('report_%d.txt', i)));        
        fclose(fid);        
    end
end

%==========================================================================
function key = generate_key()
    key = sprintf('%d', floor(rand(1)*1000000));
end

%==========================================================================
function [state file] = get_state(root)
    file = fullfile(root, 'scripts', 'state');
    if exist(file) == 2
        state = load(fullfile(root, 'scripts', 'state'), '-ascii');
    else
        state = 0;
    end
end

%==========================================================================
function set_state(task_id, state)
    % States are:
    % - 0: initial state
    % - 1: set when all jobs are launched
    % - 2: set when task finished with errors
    % - 3: set when task finished with 'KeepTmp' option
    global APT_PARAMS;
    file = fullfile(APT_get_drive(), APT_PARAMS.temp_dir, task_id, 'scripts', 'state');
    state = sprintf('%d', state);
    fid = fopen(file, 'w');
    fwrite(fid, state, 'char');
    fclose(fid);
end

%==========================================================================
function kill_jobs(params)   
    global APT_PARAMS;    
    [~, ids] = system(sprintf('cat %s 2> /dev/null | sed -e ''s:\\([0-9]*\\)@[a-zA-Z0-9_\\-]* :\\1 :g''', fullfile(APT_get_drive(), APT_PARAMS.temp_dir, params.task_id, 'scripts', 'started*')));
    if ~isempty(ids)
        fprintf('Killing jobs...\n');
        if params.UseCluster            
            [~, ~] = system(sprintf('ssh %s "qdel %s"', APT_PARAMS.cluster_IP{params.ClusterID}, ids));
        else            
            [~, ~]  = system(sprintf('kill -s 9 %s', ids));
        end
    end
end

%==========================================================================
function dirs = find_user_paths()
    dirs = path2cell();
    n_dirs = length(dirs);
    len_root = length(matlabroot);
    
    select = false(n_dirs, 1);
    for i = 1 : n_dirs
        if length(dirs{i}) < len_root
            select(i) = 1;
        else
            if ~strcmp(matlabroot, dirs{i}(1 : len_root))
                select(i) = 1;    
            end
        end
    end    
    dirs = dirs(select);
end

%==========================================================================
function dirs = path2cell()
    p = path();
    index = [0 strfind(p, pathsep) (length(p)+1)];
    n_dirs = length(index) - 1;
    dirs = cell(1, n_dirs);
    for i = 1 : n_dirs
        dirs{i} = p((index(i)+1) : (index(i+1)-1));
    end
end

%==========================================================================
function [jobs_info errors] = update_jobs_info(params, jobs_info, remove_errors)
    global APT_PARAMS;
    
    if nargin < 3
        remove_errors = 0;
    end

    drive = APT_get_drive();
    res_dir = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'res');
    sh_dir  = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts');
    errors = zeros(1, params.NJobs);
    for i = 1 : params.NJobs        
        if ~jobs_info(i).finished
            file = fullfile(res_dir, sprintf('res%d.mat', i));
            if exist(file, 'file') == 2                
                try
                    load(file, 'E'); % load args, time and E eventually                    
                catch E
                end
                if exist('E', 'var') == 1 && ~isempty(E)
                    if remove_errors                        
                        delete(file);
                        try
                            [s,m] = system(sprintf('rm -f %s', fullfile(sh_dir, sprintf('launched%d', i))));
                        catch
                        end
                        jobs_info(i).error = 1;
                    else
                        jobs_info(i).res = E;
                        jobs_info(i).error = 1;
                        jobs_info(i).started = 1;
                        jobs_info(i).finished = 1;          
                        errors(i) = 1;                        
                    end
                else
                    try
                        if ~params.NoLoad
                            load(file, 'res', 'time', 'mem');
                            jobs_info(i).res = res;
                        else
                            load(file, 'time', 'mem');
                            jobs_info(i).res = [];
                        end
                        jobs_info(i).time = time;
                        if exist('mem', 'var') 
                            jobs_info(i).mem = mem;
                        else
                            jobs_info(i).mem = [];
                        end
                    catch E  % when files are corrupted, some variables may be missing
                        if remove_errors                        
                            delete(file);
                            try
                                [s,m] = system(sprintf('rm -f %s', fullfile(sh_dir, sprintf('launched%d', i))));
                            catch
                            end
                            jobs_info(i).error = 1;
                        else
                            jobs_info(i).res = E;
                            jobs_info(i).error = 1;
                            jobs_info(i).started = 1;
                            jobs_info(i).finished = 1;          
                            errors(i) = 1;                        
                        end
                    end                    
                    jobs_info(i).started = 1;
                    jobs_info(i).finished = 1; 
                    if params.Verbose >= 2
                        fprintf('*** Job %d finished successfully. ***\n', i);
                    end
                end                
                clear('res', 'time', 'E');                
            else                
                if ~jobs_info(i).launched
                    file = fullfile(sh_dir, sprintf('launched%d', i));
                    if exist(file, 'file') == 2
                        jobs_info(i).launched = params.pause_time;
                    end
                else                    
                    jobs_info(i).launched = jobs_info(i).launched + params.pause_time;
                end
                file = fullfile(sh_dir, sprintf('started%d', i));
                if ~jobs_info(i).started && exist(file, 'file') == 2
                    jobs_info(i).started = 1;                    
                end   
            end                    
        end
    end
    errors = find(errors);
end
    
%==========================================================================
function launch_jobs(params, job_ids)
    global APT_PARAMS;
    
    libs = reshape(APT_PARAMS.default_libs, 1, numel(APT_PARAMS.default_libs));
    libs = [libs reshape(params.Libs, 1, numel(params.Libs))];
    
    drive = APT_get_drive();
    stop_file = fullfile(APT_PARAMS.temp_dir, params.task_id, 'scripts', 'stop');
    fid = fopen(fullfile(drive, stop_file), 'w');
    fprintf(fid, '0');
    fclose(fid);
    
    set_state(params.task_id, 0);    
    if params.UseCluster
        launch_on_cluster(params, job_ids, stop_file);
    else
        for i = job_ids
            launch_on_local(params, i, stop_file);    
        end
    end    
    set_state(params.task_id, 1);
        
    fid = fopen(fullfile(drive, stop_file), 'r');    
    stopped = str2double(char(fread(fid, 1, 'char')));
    fclose(fid);
    if stopped ~= 1 && params.WaitEnd
        % In case of CTRL+C, the script continues.
        % We set stop to 2 to avoid this.
        fid = fopen(fullfile(drive, stop_file), 'w');      
        fprintf(fid, '2');             
        fclose(fid);                   
        set_state(params.task_id, 2);
        error('Operation terminated by user.');
    end
end

%==========================================================================
function path = make_path(libs)
    if isempty(libs)
        path = '';
    else
        path = sprintf(sprintf('%s%%s', pathsep), libs{:});
    end
end

%==========================================================================
function msg = make_error_msg(E)
    msg = sprintf('%s\n', E.message);
    for i=1:length(E.stack)
        msg = [msg sprintf('In ==> %s at %d\n', E.stack(i).name, E.stack(i).line)];
    end
end

%==========================================================================
function launch_on_local(params, job_id, stop_file)
    % Use -nodesktop instead -nojvm if you need to start the Java Virtual Machine
    global APT_PARAMS;
    
    drive = APT_get_drive();
    fid = fopen(fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts', sprintf('launched%d', job_id)), 'w');  
    fclose(fid);
    
    matlab = fullfile(matlabroot, 'bin', 'matlab');       
    
    params.fun = regexprep(regexprep(params.fun, '''', ''''''), '("|*|\\)', '\\$1'); 
    
    p = [];
    if params.NSlots == 1
        p = [p ' -singleCompThread'];
    end
    if params.NoJVM
        p = [p ' -nojvm'];
    end
    cmd = sprintf([matlab ' -nosplash -nodesktop%s -r "cd ''%s''; addpath(''%s''); %s(''%s'', ''%d'', ''%s'', ''0''); exit;"'], p, cd(), fileparts(which(mfilename())), APT_PARAMS.main_func, params.task_id, job_id, params.fun);
    log_file = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'logs', sprintf('report_%d.txt', job_id));

    cmd = [cmd ' > ' log_file ' &'];            
    [s,r] = system(cmd);
    
    fid = fopen(fullfile(drive, stop_file), 'w');
    fprintf(fid, '1');
    fclose(fid);    
end 

%==========================================================================
function launch_on_cluster(params, job_ids, stop_file)
    global APT_PARAMS;
                
    job_file = generate_jobs(params, job_ids);        
    entry_point = generate_launcher(params, job_file, stop_file);
    
    cmd = sprintf('ssh %s %s %d', APT_PARAMS.cluster_IP{params.ClusterID}, fullfile(APT_get_drive([], params.ClusterID), entry_point), prod(APT_PARAMS.cluster_arch{params.ClusterID}(1 : 2)));

    if params.Verbose >= 2
        system(cmd);
    else
        [s,r] = system(cmd);        
    end            
end

%==========================================================================
function job_file = generate_jobs(params, job_ids)    
    global APT_PARAMS;    

    sh_dir = fullfile(APT_PARAMS.temp_dir, params.task_id, 'scripts');       
    
    job_file = fullfile(sh_dir, 'jobs.txt');
    fid=fopen(fullfile(APT_get_drive(), job_file), 'w');
    for i = 1 : length(job_ids)
        fprintf(fid, '%d\n', job_ids(i));        
    end
    fclose(fid);  
end

%==========================================================================
function cluster_choice = choose_cluster(params)
    global APT_PARAMS;    
    
    if params.Verbose >= 2
        fprintf('Automatic cluster choice...\n');
    end
    
    if isempty(APT_PARAMS.cluster_IP) 
        cluster_choice = 0;
        if params.Verbose >= 2        
            fprintf('No cluster registred.\n');
        end   
        return;
    end           
    
    [s,m]=system('hostname');
    if strcmp(m(1:4), 'node')
        if params.Verbose >= 2        
            fprintf('Running on a node. Determining master.\n');
        end
        for i = 1 : length(APT_PARAMS.cluster_IP)
            [s,m]=system(sprintf('ssh %s date', APT_PARAMS.cluster_IP{i}));
            if s == 0
                cluster_choice = i;
                if params.Verbose >= 2        
                    fprintf('Launching jobs on %s.\n', APT_PARAMS.cluster_IP{cluster_choice});
                end                
                return;
            end
        end
    end
        
    meleze_arch = APT_PARAMS.cluster_arch{1};
    if params.Memory > meleze_arch(3) * 1000
        cluster_choice = 2;
        if params.Verbose >= 2   
            fprintf('You are requesting to much memory for Meleze, launching jobs on %s.\n', APT_PARAMS.cluster_IP{cluster_choice});
        end
        return;
    end    
               
    drive = APT_get_drive();
    local_counter = fullfile(APT_PARAMS.temp_dir, params.task_id, 'scripts', 'local_counter.sh');
    fid = fopen(fullfile(drive, local_counter), 'w');
    fprintf(fid,'#!/bin/bash \n');
    fprintf(fid,'njobs=`qstat -u "*" | sed "1d; 2d; s/.* \\([0-9][0-9]*\\) *$/\\1/" | echo \\`sum=0; while read line; do let sum=$sum+$line; done; echo $sum\\` `; \n');
    fprintf(fid,'echo $njobs \n');    
    fclose(fid);
    
    job_counter = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts', 'counter.sh');
    fid = fopen(job_counter, 'w');
    fprintf(fid,'#!/bin/bash \n');
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,'njobs=`ssh %s "module add sge cluster-tools; sh %s"` \n', APT_PARAMS.cluster_IP{i}, fullfile(APT_get_drive([], i), local_counter));
        fprintf(fid,'echo $njobs \n');                  
    end
    fclose(fid);
    
    choice = fullfile(drive, APT_PARAMS.temp_dir, params.task_id, 'scripts', 'cluster_choice.txt');
    system(sprintf('sh %s > %s', job_counter, choice));
    
    coeff = ones(length(APT_PARAMS.cluster_IP), 1);    
    n_slots = zeros(length(APT_PARAMS.cluster_IP), 1);      
    for i = 1 : length(APT_PARAMS.cluster_IP)
        cluster_arch = APT_PARAMS.cluster_arch{i};
        n_slots(i) = cluster_arch(1) * cluster_arch(2);
        if params.Memory  
            mem_per_slot = cluster_arch(3) * 1000 / cluster_arch(2);
            coeff(i) = max(1, params.Memory / mem_per_slot);
        end                     
    end
    
    njobs = load(choice);
    free_slots = n_slots - njobs;
    coeff_free_slots = free_slots ./ coeff;
    if params.Verbose >= 2   
        for i = 1 : length(APT_PARAMS.cluster_IP)
            fprintf('On %s: %d jobs available (%d free slots).\n', APT_PARAMS.cluster_IP{i}, round(coeff_free_slots(i)), free_slots(i));
        end
    end
    [m cluster_choice] = max(coeff_free_slots);    
    
    if params.Verbose >= 2        
        fprintf('Launching jobs on %s.\n', APT_PARAMS.cluster_IP{cluster_choice});
    end
end

%==========================================================================
function script = generate_launcher(params, job_file, stop_file)
    global APT_PARAMS; 
    
    drive = APT_get_drive();
    cluster_drive = APT_get_drive([], params.ClusterID);
    job_file = fullfile(cluster_drive, job_file);
    stop_file = fullfile(cluster_drive, stop_file);
    
    sh_dir  = fullfile(APT_PARAMS.temp_dir, params.task_id, 'scripts');        
    job_limit_file = fullfile(cluster_drive, APT_PARAMS.temp_dir, [APT_PARAMS.cluster_IP{params.ClusterID} '.inf']); 
                   
    script = fullfile(sh_dir,'launcher.sh');
    fid = fopen(fullfile(drive, script),'w');
    % We count the number of used cores
    cmdcount = sprintf('$QSTAT -u "%s" | sed "1d; 2d; s/.* \\([0-9][0-9]*\\) *$/\\1/" | echo \\`sum=0; while read line; do let sum=$sum+$line; done; echo $sum\\` ', APT_PARAMS.login);
    allcount = '$QSTAT -u "*" | sed "1d; 2d; s/.* \([0-9][0-9]*\) *$/\\1/" | echo \`sum=0; while read line; do let sum=$sum+$line; done; echo $sum\` ';
    numjob = '$QSTAT -u "*" | grep $USER | wc -l';
    fprintf(fid,'#!/bin/sh\n');
    fprintf(fid,'cd %s\n', fullfile(cluster_drive, sh_dir));
    fprintf(fid,'module add sge cluster-tools\n');
    fprintf(fid,'QSTAT="qstat"\n');
    fprintf(fid,'QSUB="qsub"\n');
    fprintf(fid,['USER=' APT_PARAMS.login '\n']);
    fprintf(fid,['CODESH=' job_file '\n']);
    fprintf(fid,['FOLDER=' fullfile(cluster_drive, sh_dir) '\n']);
    fprintf(fid,'cd $FOLDER\n');
    fprintf(fid,'QUEUE=$1\n');
    fprintf(fid,'SUFF=withoutSpaces.txt\n');
    fprintf(fid,'CODESH2=$CODESH$SUFF\n'); 
    fprintf(fid,'sed ''/^$/d'' $CODESH > $CODESH2\n');
    fprintf(fid,'MAXJOB=$(cat %s)\n',  job_limit_file);      
    fprintf(fid,'while read JOBID\n');
    fprintf(fid,'do\n');
    fprintf(fid,'	COUNTERJOBS=`%s`\n', allcount);     
    fprintf(fid,'   if [ "$COUNTERJOBS" -ge "$QUEUE" ]; then\n');       
    fprintf(fid,'       date "+[%%d-%%b-%%Y %%T] Task %s: Cluster queue is full, waiting for free slots."\n', params.task_id);     
    fprintf(fid,'       LAST=`%s`\n', numjob);
    fprintf(fid,'       if [ "$LAST" -ne "0" ]; then\n');
    fprintf(fid,'           NEWLAST=$LAST\n');
    fprintf(fid,'           while [ "$NEWLAST" -eq "$LAST" ]; do\n');    
    fprintf(fid,'               sleep 10\n');
    fprintf(fid,'               NEWLAST=`%s`\n', numjob);  
    fprintf(fid,'           done\n');    
    fprintf(fid,'       fi\n'); 
    fprintf(fid,'   fi\n');        
    fprintf(fid,'	COUNTERJOBS=`%s`\n', cmdcount);    
    fprintf(fid,'   if [ "$COUNTERJOBS" -ge "$MAXJOB" ]; then\n');
    fprintf(fid,'       date "+[%%d-%%b-%%Y %%T] Task %s: Job number limit reached ($COUNTERJOBS/$MAXJOB slots used)."\n', params.task_id); 
    fprintf(fid,'       while [ "$COUNTERJOBS" -ge "$MAXJOB" ]; do\n');
    fprintf(fid,'           sleep 10\n');
    fprintf(fid,'           COUNTERJOBS=`%s`\n', cmdcount);
    fprintf(fid,'           NEWMAXJOB=$(cat %s)\n', job_limit_file);
    fprintf(fid,'           if [ "$NEWMAXJOB" -ne "$MAXJOB" ]; then\n');
    fprintf(fid,'               MAXJOB=$NEWMAXJOB\n');
    fprintf(fid,'               date "+[%%d-%%b-%%Y %%T] Task %s: Job number limit reached ($COUNTERJOBS/$MAXJOB slots used)."\n', params.task_id);     
    fprintf(fid,'           fi\n');    
    fprintf(fid,'        done\n');
    fprintf(fid,'    fi\n');    
    fprintf(fid,'    stop=$(cat %s)\n', stop_file);    
    fprintf(fid,'    if [ "$stop" -ne "0" ]; then\n');
    fprintf(fid,'        break\n');
    fprintf(fid,'    fi\n');        
    fprintf(fid,'    date "+[%%d-%%b-%%Y %%T] Task %s: " | tr -d "\\n"\n', params.task_id);
    fprintf(fid,'    $QSUB %s\n', fullfile(cluster_drive, sh_dir, 'submit$JOBID.pbs'));    
    fprintf(fid,'    sleep 0.1\n');
    fprintf(fid,'done < $CODESH2\n');
    fprintf(fid,'echo "1" > %s\n', stop_file);    
    fclose(fid);    
    
    system(['chmod 711 ' fullfile(drive, script)]);
end

function makeCoffe()
fprintf('Buffering coffee beans...\n');
pause(2);
fprintf('Boiling CPU...\n');
pause(2);
fprintf('Pressuring stream...\n');
pause(2);
fprintf('Adding syntactic sugar...\n');
pause(2);


fprintf('\n');
fprintf('                        (\n');
fprintf('                          )     (\n');
fprintf('                   ___...(-------)-....___\n');
fprintf('               .-""       )    (          ""-.\n');
fprintf('         .-''``''|-._             )         _.-|\n');
fprintf('        /  .--.|   `""---...........---""`   |\n');
fprintf('       /  /    |                             |\n');
fprintf('       |  |    |                             |\n');
fprintf('        \\  \\   |                             |\n');
fprintf('         `\\ `\\ |                             |\n');
fprintf('           `\\ `|                             |\n');
fprintf('           _/ /\\                             /\n');
fprintf('          (__/  \\                           /\n');
fprintf('       _..---""` \\                         /`""---.._\n');
fprintf('    .-''           \\                       /          ''-.\n');
fprintf('   :               `-.__             __.-''              :\n');
fprintf('   :                  ) ""---...---"" (                 :\n');
fprintf('    ''._               `"--...___...--"`              _.''\n');
fprintf('      \\""--..__                              __..--""/\n');
fprintf('       ''._     """----.....______.....----"""     _.''\n');
fprintf('          `""--..,,_____            _____,,..--""`\n');
fprintf('                        `"""----"""`''\n');

fprintf('\nEnjoy !\n');
end