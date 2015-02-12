function APT_jn_set(njobs, clusterID)
    global APT_PARAMS;
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    file = [fullfile(APT_get_drive(), APT_PARAMS.temp_dir, mfilename()) '.sh'];    
    
    if nargin < 1
        njobs = [];
    else
        njobs = num2str(njobs);
    end
    
    if nargin < 2
        clusterID = [];
    else
        clusterID = num2str(clusterID);
    end
    
    system(sprintf('%s %s %s', file, njobs, clusterID));
end