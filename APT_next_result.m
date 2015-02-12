function [jobID, varargout] = APT_next_result(tID)
    global APT_PARAMS;
    persistent indexMap nfilesMap;
    
    if ~ischar(tID)
        tID = num2str(tID);
    end
    
    if isempty(APT_PARAMS)
        APT_params();
    end  
    if isempty(indexMap)
        indexMap = containers.Map;
    end
    if isempty(nfilesMap)
        nfilesMap = containers.Map;
    end
    
    argdir = fullfile(APT_get_drive(APT_PARAMS.temp_drive), APT_PARAMS.temp_dir, tID, 'args');
    tmpdir = fullfile(APT_get_drive(APT_PARAMS.temp_drive), APT_PARAMS.temp_dir, tID, 'res');
    
    if isKey(indexMap, tID)
        index = indexMap(tID);
        nfiles = nfilesMap(tID);
    else
        index = [1 1 0];
        load(fullfile(APT_get_drive(APT_PARAMS.temp_drive), APT_PARAMS.temp_dir, tID, 'scripts', 'params.mat'), 'params');
        nfiles = params.NJobs;
        indexMap(tID) = index;        
        nfilesMap(tID) = nfiles;
    end    
    
    fID = index(1);
    rID = index(2);
    jobID = index(3);
    done = false;
    while fID <= nfiles
        try
            load(fullfile(tmpdir, sprintf('res%d.mat', fID)), 'res');
            nres = size(res, 1);
            if rID > nres
                fID = fID + 1;
                rID = 1;
            else
                res = res(rID, :);
                rID = rID + 1;
                jobID = jobID + 1;
                if rID > nres
                    fID = fID + 1;
                    rID = 1;
                end
                done = true;
                break;
            end
        catch E
            load(fullfile(argdir, sprintf('args%d.mat', fID)), 'jobIDs');
            fID = fID + 1;
            rID = 1;
            jobID = jobID + length(jobIDs);
        end
    end
    
    if ~done
        jobID = [];
        for i = 1 : nargout
            varargout{i} = [];
        end
        remove(indexMap, tID);
        remove(nfilesMap, tID);
    else
        for i = 1 : (nargout - 1)
            varargout{i} = res{i};
        end
        index = [fID rID jobID];
        indexMap(tID) = index;
    end
end