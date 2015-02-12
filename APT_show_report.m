function APT_show_report(taskID, jobID)
    global APT_PARAMS;
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    file = [fullfile(APT_get_drive(), APT_PARAMS.temp_dir, mfilename()) '.sh'];
        
    if nargin < 1
        taskID = [];
    else
        taskID = num2str(taskID);
    end
    
    if nargin < 2
        jobID = [];
    else
        jobID = num2str(jobID);
    end
    
    system(sprintf('%s %s %s', file, taskID, jobID));
end