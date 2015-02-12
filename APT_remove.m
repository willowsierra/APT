function APT_remove(removeAfterNDays)
    global APT_PARAMS;
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    if nargin < 2
        removeAfterNDays = 7;
    end
    
    file = [fullfile(APT_get_drive(), APT_PARAMS.temp_dir, mfilename()) '.sh'];      
    
    system(sprintf('%s %d', file, removeAfterNDays));
end