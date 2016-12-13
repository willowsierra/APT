function APT_params()
    global APT_PARAMS;
    
    %!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!%
    %!!                                                                 !!%    
    %!! This file is not loaded twice: if you modify it, run            !!%
    %!! 'APT_params' to update the parameters. You can also modify the  !!%
    %!! global variable 'APT_PARAMS' by hand to apply changes only for  !!%
    %!! this matlab session.                                            !!%
    %!!                                                                 !!%
    %!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!%
    
    % User parameters 
    %================
    
    % SSH login on the cluster.
    APT_PARAMS.login = getenv('USER');    
    
    % The drive for toolbox temporary files.
    % It has to be either: 'data', 'scratch', 'data0Meleze', 'data1Meleze',
    % 'data2Meleze' or 'data1Sequoia'
    APT_PARAMS.temp_drive = 'data1Sequoia';
    
    % The directory for toolbox temporary files.    
    % It will be created in APT_PARAMS.temp_drive
    APT_PARAMS.temp_dir = fullfile(APT_PARAMS.login, 'tmp');
    
    % The name for the binary produced by mcc. 
    % You can change it dynamically if you have different projects: by also 
    % changing your path appropriatly you can make compilation faster.
    APT_PARAMS.exec_name = 'my_exec';
    
    % The private workspace directory.
    % Each job will be assign to a subdirectory of /local/your_login/loc_dir
    % so that it can store data on local disk safely (see JOB_INFO.user_dir).
    % This directory is removed when the job ends.
    APT_PARAMS.loc_dir = 'tmp';      
    
    % Force cluster choice : 1 for meleze, 2 for sequoia, 0 for no forcing
    APT_PARAMS.cluster_id = 0;         
    
    % Specify nodes which should be used, e.g. use: '{'node017', 'node018',
    % 'node019', 'node020'}' on Sequoia to run on the nodes which have more 
	% memory. Default is set in 'APT_params' and launch the jobs on any node.
    APT_PARAMS.host_name = {};

    % Force local computation. It has priority over 'cluster_id'.
    APT_PARAMS.force_local = 0;           
    
    % Verbosity level : 0, 1 or 2.
    APT_PARAMS.verbose = 2;  
    
    % Shared libraries you use (one cell entry per library)
    APT_PARAMS.default_libs = {};                                               
    
    % Default number of cores used when running on your local machine.
    % If null it will use all your cores.    
    APT_PARAMS.numcores = 0;   
     
    % ToolBox intern parameters % 
    %============================
    
    % ***** DO NOT EDIT AFTER THIS LINE UNLESS YOU KNOW WHAT YOU DO ***** %
    
    % Default job limit on cluster.
    APT_PARAMS.default_job_number = 30;
    
    % IP address of each cluster.
    APT_PARAMS.cluster_IP = {'meleze' 'sequoia'};

    % Architecture of each cluster (#nodes #core/node VMem Swap)
    APT_PARAMS.cluster_arch = {[16 8 16 16] [20 12 46 16]};
    
    % Entry point (main function).
    APT_PARAMS.main_func = 'APT_entry_point';     
        
    % Paths the drives: one row per drive: ID, Path Local, Meleze, Sequoia
    APT_PARAMS.drives = { ...
        'scratch'      '/scratch/'       '/scratch/'       '/scratch/'; ...
        'data'         '/meleze/data0/'  '/meleze/data0/'  '/meleze/data0/'; ...  % for compatibility, same as 'data0Meleze'
        'data0Meleze'  '/meleze/data0/'  '/meleze/data0/'  '/meleze/data0/'; ...
        'data1Meleze'  '/meleze/data1/'  '/meleze/data1/'  '/meleze/data1/'; ...        
        'data2Meleze'  '/meleze/data2/'  '/meleze/data2/'  '/meleze/data2/'; ...
        'data1Sequoia' '/sequoia/data1/' '/sequoia/data1/' '/sequoia/data1/'; ...
        };
    
    % MCR paths: one row per entry: matlab root directory, path to MCR
    % should have an entry default.
    APT_PARAMS.MCR = { ...
        'matlab-2009b' '/local/MCR/v711'; ...
        'matlab-2010b' '/local/MCR/v714'; ...
        'matlab-2011a' '/local/MCR/v715'; ...        
        'matlab-2012a' '/local/MCR/v717'; ...        
        'matlab-2013b' '/local/MCR/v82'; ...        
        'matlab-2014b' '/local/MCR/v84'; ...        
        'matlab-2015a' '/local/MCR/v85'; ...        
        'matlab-2016a' '/local/MCR/v901'; ...        
        };

    % Default queues for each cluster:
    APT_PARAMS.queues = { {'all.q'} {'goodboy.q', 'all.q', 'bigmem.q'} };
    
    % Generating script files
    generate_utilities();
end

%==========================================================================
function generate_utilities()
    global APT_PARAMS; 
    drive = APT_get_drive();
    
    versionfile = fullfile(drive, APT_PARAMS.temp_dir, 'version.inf');    
    if exist(versionfile, 'file') == 2
        fid = fopen(versionfile, 'rt');
        version = str2double(fread(fid, Inf, '*char')');
        fclose(fid);
        if version == APT_version()
            return;
        end
    else
        [s, m] = mkdir(fullfile(drive, APT_PARAMS.temp_dir));
    end
       
    % Compile APT_getpid
    currdir = cd();
    APTdir = fileparts(mfilename('fullpath'));    
    if ~exist(fullfile(APTdir, ['APT_getpid.' mexext()]), 'file')
        cd(APTdir);
        mex APT_getpid.c
        cd(currdir);    
    end
    
    % write job limits    
    for i = 1 : length(APT_PARAMS.cluster_IP)
        file = fullfile(drive, APT_PARAMS.temp_dir, [APT_PARAMS.cluster_IP{i} '.inf']);
        if exist(file, 'file') ~= 2
            fid=fopen(file, 'wt');
            fprintf(fid, '%d', APT_PARAMS.default_job_number);
            fclose(fid);
        end
        fileattrib(file,'+w', 'g', 's'); 
    end
    
    % APT_jn_set
    file = fullfile(drive, APT_PARAMS.temp_dir, 'APT_jn_set.sh');   % if changed, change also the name corresponding matlab function
    fid=fopen(file,'w');
    fprintf(fid,'#!/bin/sh \n');
    fprintf(fid,'exe_dir=`dirname $0` \n');       
    fprintf(fid,'if [ $# -eq 0 ]; then\n');            
    fprintf(fid,'  echo "To set the job limit use: $0 [job_limit] [cluster_id]" \n');
    fprintf(fid,'  echo "Currently the limits are:" \n');
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,'  l=`cat ${exe_dir}/%s.inf` \n', APT_PARAMS.cluster_IP{i});    
        fprintf(fid,'  echo "- %s: $l slots." \n', APT_PARAMS.cluster_IP{i});    
    end
    fprintf(fid,'else\n');     
    fprintf(fid,'  if [ $# -eq 1 ]; then\n');             
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,'    echo $1 > ${exe_dir}/%s.inf \n', APT_PARAMS.cluster_IP{i});    
    end   
    fprintf(fid,'    echo Job number limit set to $1 for:%s\n', sprintf(' %s', APT_PARAMS.cluster_IP{:}));    
    fprintf(fid,'  else\n');     
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,['    if [ "$2" = "' APT_PARAMS.cluster_IP{i} '" -o $2 -eq ' num2str(i) ' ]; then\n']);         
        fprintf(fid,'      echo $1 > ${exe_dir}/%s.inf \n', APT_PARAMS.cluster_IP{i});    
        fprintf(fid,'    echo Job number limit set to $1 for: %s\n', APT_PARAMS.cluster_IP{i});    
        fprintf(fid,'    else\n'); 
    end    
    fprintf(fid,'        echo Unknown cluster id. It should be:\n');
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,'        echo - %d for %s\n', i, APT_PARAMS.cluster_IP{i});    
    end
    for i = 1 : length(APT_PARAMS.cluster_IP)
        fprintf(fid,'    fi\n');   
    end    
    fprintf(fid,'  fi\n');     
    fprintf(fid,'fi\n');     
    fclose(fid);    
    system(['chmod 711 ' file]);
    
    
    % APT_show_report
    file = fullfile(drive, APT_PARAMS.temp_dir, 'APT_show_report.sh');  % if changed, change also the name corresponding matlab function
    fid=fopen(file,'w');    
    fprintf(fid,'#!/bin/sh \n');
    fprintf(fid,'exe_dir=`dirname $0` \n');       
    fprintf(fid,'if [ $# -le 1 ]; then\n');            
    fprintf(fid,'  echo "Utility:" \n');
    fprintf(fid,'  echo "$0 TaskID JobID" \n');
    fprintf(fid,'else\n');         
    fprintf(fid,'  cat ${exe_dir}/$1/logs/report_$2.txt\n');     
    fprintf(fid,'  echo "" \n');
    fprintf(fid,'fi\n');     
    fclose(fid);
    system(['chmod 711 ' file]);   
    
    % APT_clean
    file = fullfile(drive, APT_PARAMS.temp_dir, 'APT_remove.sh');  % if changed, change also the name corresponding matlab function    
    fid=fopen(file,'w');    
    fprintf(fid,'#!/bin/sh\n');
    fprintf(fid,'if [ "$#" -lt "1" ]; then\n');
    fprintf(fid,'    nbdays=7;\n');
    fprintf(fid,'else\n');
    fprintf(fid,'    nbdays=$1;\n');
    fprintf(fid,'fi;\n');
    fprintf(fid,'if [ "$nbdays" -eq "0" ]; then\n');
    fprintf(fid,'    echo "All tasks will be removed, please wait...";\n');
    fprintf(fid,'else\n');
    fprintf(fid,'    echo "All tasks older than $nbdays day(s) will be removed, please wait...";\n');
    fprintf(fid,'fi;\n');
    fprintf(fid,'exe_dir=`dirname $0` ;\n');
    fprintf(fid,'now=`date +%%s`;\n');
    fprintf(fid,'for task in `ls $exe_dir | grep "^[0-9][0-9]*"`; do\n');
    fprintf(fid,'    if [ "$nbdays" -gt "0" ]; then\n');
    fprintf(fid,'        file=$exe_dir/$task/scripts/state;\n');
    fprintf(fid,'        remove=0;\n');
    fprintf(fid,'        if [ ! -e "$file" ]; then\n');
    fprintf(fid,'            echo "Task $task: No stat file, removed.";\n');
    fprintf(fid,'            remove=1;\n');
    fprintf(fid,'        else\n');
    fprintf(fid,'            state=`cat $file`;\n');
    fprintf(fid,'            state=`echo $state | sed -e "s:\\([0-9]*\\)\\.*.*:\\1:"`;  #get rid of decimal part\n');
    fprintf(fid,'            if [ "$state" -eq "0" ]; then\n');
    fprintf(fid,'                echo "Task $task: Launching jobs.";\n');
    fprintf(fid,'            elif [ "$state" -eq "1" ]; then\n');
    fprintf(fid,'                echo "Task $task: Running.";\n');
    fprintf(fid,'            elif [ "$state" -eq "3" ]; then\n');
    fprintf(fid,'                echo "Task $task: KeepTmp enabled, PLEASE REMOVE TASK MANUALLY: $exe_dir/$task";\n');
    fprintf(fid,'            else\n');
    fprintf(fid,'                modif=`stat -c %%Y $file`;\n');
    fprintf(fid,'                nd=$((($now - $modif) / 3600 / 24));\n');
    fprintf(fid,'                if [ "$nd" -ge "$nbdays" ]; then\n');
    fprintf(fid,'                    echo "Task $task: Terminated since $nd day(s), removed.";\n');
    fprintf(fid,'                    remove=1;\n');
    fprintf(fid,'                else\n');
    fprintf(fid,'                    echo "Task $task: Terminated since $nd day(s), kept.";\n');
    fprintf(fid,'                fi;\n');
    fprintf(fid,'            fi;\n');
    fprintf(fid,'        fi;\n');
    fprintf(fid,'    else\n');
    fprintf(fid,'        echo "Removing task $task.";\n');
    fprintf(fid,'        remove=1;\n');
    fprintf(fid,'    fi;\n');
    fprintf(fid,'    if [ "$remove" -eq "1" ]; then\n');
    fprintf(fid,'        rm -rf $exe_dir/$task;\n');
    fprintf(fid,'    fi;\n');
    fprintf(fid,'done;\n');
    fclose(fid);
    system(['chmod 711 ' file]);    
    
    % APT_missing_jobs
    file = fullfile(drive, APT_PARAMS.temp_dir, 'APT_missing_jobs.sh');  % if changed, change also the name corresponding matlab function
    fid=fopen(file,'w');    
    fprintf(fid,'#!/bin/sh \n');
    fprintf(fid,'exe_dir=`dirname $0` \n');       
    fprintf(fid,'if [ $# -le 0 ]; then \n');            
    fprintf(fid,'  echo "Utility:" \n');
    fprintf(fid,'  echo "$0 TaskID" \n');
    fprintf(fid,'else\n');         
    fprintf(fid,'  NJOBS=`ls ${exe_dir}/$1/scripts/launched* | wc -l` \n');     
    fprintf(fid,'  for ((i = 1; i <= $NJOBS; i++)) \n');
    fprintf(fid,'  do \n');
    fprintf(fid,'    ISRES=`ls ${exe_dir}/$1/res/ | grep "res$i.mat" | wc -l` \n');
    fprintf(fid,'    if [ $ISRES -eq 0 ] \n');
    fprintf(fid,'    then \n');
    fprintf(fid,'      echo $i; \n');
    fprintf(fid,'    fi \n');
    fprintf(fid,'  done \n');
    fprintf(fid,'fi\n');     
    fclose(fid);
    system(['chmod 711 ' file]);    
    
    % Updates version
    version = APT_version();
    fid=fopen(versionfile, 'wt');
    fprintf(fid, '%g', version);
    fclose(fid);
    save(versionfile, 'version', '-ascii');
end
