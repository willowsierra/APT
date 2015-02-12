function APT_compile(varargin)
    global APT_PARAMS;
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    %======================================================================
    
    params = struct('NoJVM', 1, ...
                    'SingleThread', 1, ...
                    'Ignore', {{}});
                
    %======================================================================
    
    fun_names = {};
    i = 1;
    while i <= length(varargin)
        if iscell(varargin{i})
            fun_names = [fun_names varargin{i}];
        elseif ischar(varargin{i})
            f = fields(params);
            fID = find(strcmp(varargin{i}, f), 1);
            if ~isempty(fID)
                params.(f{fID}) = varargin{i+1};
                i = i + 2;
                continue;
            else
                if strcmp(which(varargin{i}), '') 
                    error('Arguments should function names or options, unable to find: %s ', varargin{i});
                else
                    fun_names = [fun_names {varargin{i}}];
                end
            end                
        else
            error('Arguments should function names or options.');
        end
        i = i + 1;
    end
    
    if nargin < 1
        fun_names = {};
    elseif iscell(fun_names)
        for i = 1 : length(fun_names)
            if ~ischar(fun_names{i})                
                error('First argument should be a cell of strings or a string.');
            end
        end
    else
        if ischar(fun_names)
            fun_names = {fun_names};
        else
            error('First argument should be a cell of strings or a string.');
        end
    end
    for i = 1 : length(fun_names)
        if strcmp(fun_names{i}(end-1:end), '.m')
            fun_names{i} = fun_names{i}(1:end-2);
        end
    end
        
    drive = APT_get_drive();
    temp_dir = fullfile(drive, APT_PARAMS.temp_dir);
    [s,m] = mkdir(temp_dir);
                
    % Compiling  
    if isempty(fun_names)
        src_path = get_src_path(params.Ignore);
        src_path = sprintf(' -a %s', src_path{:});  
    else
        src_path = sprintf(' -a %s', fun_names{:});        
    end    
    flags = '';
    if params.NoJVM
        fprintf('Use APT_compile(''NoJVM'', 0) to compile with the JVM\n');
        flags = [flags '-R -nojvm '];
    end
    if params.SingleThread
        fprintf('Use APT_compile(''SingleThread'', 0) to compile with multi-threading\n');
        flags = [flags '-R -singleCompThread '];
    end    
    fprintf('Compiling, it may take some time...\n');
    cmd = ['mcc -m -R -nodisplay ' flags '-d ' temp_dir ' -o _' APT_PARAMS.exec_name src_path ' ' APT_PARAMS.main_func];
    eval(cmd);   
    movefile(fullfile(temp_dir, ['_' APT_PARAMS.exec_name]), fullfile(temp_dir, APT_PARAMS.exec_name));      
        
    fid = fopen(fullfile(temp_dir, [APT_PARAMS.exec_name '.inf']), 'wt');
    fprintf(fid, 'flags="%s";\n', flags);
    fprintf(fid, 'funs="%s";\n', sprintf('%s ', fun_names{:}));
    fclose(fid);
  
    % Overwriting matlab runner
    generate_runner();             
    
    % Cleaning
    system(sprintf('rm %s %s %s %s', fullfile(temp_dir, '*.c'), ...
                                     fullfile(temp_dir, '*.prj'), ...
                                     fullfile(temp_dir, '*.txt'), ...
                                     fullfile(temp_dir, '*.log')));
    
    fprintf('Compilation finished successfully.\n');
end

%==========================================================================
function generate_runner()
    global APT_PARAMS; 
    
%     runner_orig = fullfile(drive, APT_PARAMS.temp_dir, ['run__' APT_PARAMS.exec_name '.sh']); 
%     runner = fullfile(drive, APT_PARAMS.temp_dir, ['run_' APT_PARAMS.exec_name '.sh']); 
%     system(sprintf('sed "/echo LD_LIBRARY_PATH/d;/\$\*/d;s|shift 1|LD_LIBRARY_PATH=\${LD_LIBRARY_PATH}:\$2\nexport LD_LIBRARY_PATH;\necho LD_LIBRARY_PATH is \${LD_LIBRARY_PATH};\nshift 2\necho \"\" > \${exe_dir}/\$1/scripts/launched\$2\n\${exe_dir}/%s \"\$1\" \"\$2\" \"\$3\" \"\$4\"|" %s > %s', APT_PARAMS.exec_name, runner_orig, runner));
    
    drive = APT_get_drive();
    runner = fullfile(drive, APT_PARAMS.temp_dir, ['run_' APT_PARAMS.exec_name '.sh']);    
    fid=fopen(runner,'w');  
    fprintf(fid, '#!/bin/sh\n');
    fprintf(fid, '# script for execution of deployed applications\n');
    fprintf(fid, '#\n');
    fprintf(fid, '# Sets up the MCR environment for the current $ARCH and executes\n');
    fprintf(fid, '# the specified command.\n');
    fprintf(fid, '#\n');
    fprintf(fid, 'exe_dir=`dirname $0`\n');
    fprintf(fid, 'echo "------------------------------------------"\n');
    fprintf(fid, 'if [ "x$1" = "x" ]; then\n');
    fprintf(fid, '  echo Usage:\n');
    fprintf(fid, '  echo    $0 \\<deployedMCRroot\\> args\n');
    fprintf(fid, 'else\n');
    fprintf(fid, '  echo Setting up environment variables\n');
    fprintf(fid, '  MCRROOT=$1\n');
    fprintf(fid, '  echo ---\n');
    fprintf(fid, '  MWE_ARCH="glnxa64" ;\n');
    fprintf(fid, '  if [ "$MWE_ARCH" = "sol64" ] ; then\n');
    fprintf(fid, '    LD_LIBRARY_PATH=.:/usr/lib/lwp:${MCRROOT}/runtime/glnxa64 ;\n');
    fprintf(fid, '  else\n');
  	fprintf(fid, '    LD_LIBRARY_PATH=.:${MCRROOT}/runtime/glnxa64 ;\n');
    fprintf(fid, '  fi\n');
    fprintf(fid, '  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRROOT}/bin/glnxa64 ;\n');
    fprintf(fid, '  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRROOT}/sys/os/glnxa64;\n');
    fprintf(fid, '  if [ "$MWE_ARCH" = "maci" -o "$MWE_ARCH" = "maci64" ]; then\n');
    fprintf(fid, '	  DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}:/System/Library/Frameworks/JavaVM.framework/JavaVM:/System/Library/Frameworks/JavaVM.framework/Libraries;\n');
    fprintf(fid, '  else\n');
    fprintf(fid, '	MCRJRE=${MCRROOT}/sys/java/jre/glnxa64/jre/lib/amd64 ;\n');
    fprintf(fid, '	LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRJRE}/native_threads ;\n');
	fprintf(fid, '  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRJRE}/server ;\n');
    fprintf(fid, '	LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRJRE}/client ;\n');
    fprintf(fid, '	LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MCRJRE} ;  \n');
    fprintf(fid, '  fi\n');
    fprintf(fid, '  XAPPLRESDIR=${MCRROOT}/X11/app-defaults ;\n');
    fprintf(fid, '  LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:$2\n');
    fprintf(fid, '  export LD_LIBRARY_PATH;\n');
    fprintf(fid, '  export XAPPLRESDIR;\n');
    fprintf(fid, '  echo LD_LIBRARY_PATH is ${LD_LIBRARY_PATH};\n');
    fprintf(fid, '  shift 2\n');
    fprintf(fid, '  echo "" > ${exe_dir}/$1/scripts/launched$2\n');
    fprintf(fid, '  ${exe_dir}/%s "$1" "$2" "$3" "$4"\n', APT_PARAMS.exec_name);
    fprintf(fid, 'fi\n');
    fprintf(fid, 'exit\n'); 
end

%==========================================================================
function src_path = get_src_path(ignore)    
    src_path = find_user_paths(ignore);
    
    toolbox_path = fileparts(which(mfilename()));
    if isempty(find(strcmp(src_path, toolbox_path), 1))
        src_path = [toolbox_path src_path];
    end
    
    if isempty(find(strcmp(src_path, cd()), 1))
        src_path = [cd() src_path];
    end
    
    src_path = repmat(reshape(src_path, 1, numel(src_path)), 2, 1);
    for i = 1 : size(src_path, 2)
        src_path{1, i} = fullfile(src_path{1, i}, '*.m');
        src_path{2, i} = fullfile(src_path{2, i}, ['*.' mexext]);
    end
    src_path = reshape(src_path, 1, numel(src_path));
    java_path = javaclasspath('-dynamic');
    src_path = [src_path reshape(java_path, 1, numel(java_path))];
end

%==========================================================================
function dirs = find_user_paths(ignore)
    dirs = path2cell();
    n_dirs = length(dirs);
    ignore{end + 1} = matlabroot;
    
    select = true(n_dirs, 1);
    for i = 1 : n_dirs
        for j = 1 : length(ignore)
            if ignore{j}(1) ~= '/'
                ignore{j} = fullfile(cd(), ignore{j});
            end
            len = length(ignore{j});
            if length(dirs{i}) >= len && strcmp(ignore{j}, dirs{i}(1 : len))
                select(i) = false;
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
    valid_dir = true(1, n_dirs);
    for i = 1 : n_dirs
        dirs{i} = p((index(i)+1) : (index(i+1)-1));
        if ~isdir(dirs{i})
            valid_dir(i) = 0;
            fprintf('Warning, invalid directory in matlab path: %s\n', dirs{i});
        end
    end
    dirs = dirs(valid_dir);
end
