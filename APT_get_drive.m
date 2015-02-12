function drive = APT_get_drive(drive_id, host_id)
    % 'drive_id' has to be either 'data', 'scratch', 'data1Meleze' or 'data1Sequoia'
    global APT_PARAMS JOB_INFO;      
    if isempty(APT_PARAMS)
        APT_params();
    end
    
    if nargin < 1 || isempty(drive_id)
        drive_id = APT_PARAMS.temp_drive;
    end
    
    if nargin < 2
        if isempty(JOB_INFO)
            [s, h] = system('hostname');
            m = regexp(h, '(\w|_|-)*', 'match');            
            m = m{1};           
            if length(m) >= 4 && strcmp('node', m(1:4))
                host_id = 1; %actually we don't know about meleze or sequoia
            else 
                host_id = find(strcmpi(m, APT_PARAMS.cluster_IP), 1);
                if isempty(host_id)
                    host_id = 0;
                end
            end
        else
            host_id = JOB_INFO.cluster_id;
        end        
    end
    
    for i = 1 : size(APT_PARAMS.drives, 1)
        if strcmp(drive_id, APT_PARAMS.drives{i, 1})
            drive = APT_PARAMS.drives{i, 2 + host_id};
            return;
        end
    end
    error('Unknown drive %s.\n', drive_id);    
end
