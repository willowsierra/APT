function APT_missing_jobs(taskID)
    global APT_PARAMS;
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    file = [fullfile(APT_get_drive(), APT_PARAMS.temp_dir, mfilename()) '.sh'];      
    
    system(sprintf('%s %d', file, taskID));
end