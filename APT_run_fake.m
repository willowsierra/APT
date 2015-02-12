function varargout = APT_run(task, varargin)      

    %======================================================================

    params = struct( ...
                    'CombineArgs', 0, ...                    
                    'Libs', {{}}, ...
                    'ShellVar', {{}}, ...
                    ... % Should not be modified
                    'KeepTmp', [], ...                    
                    'NoLoad', 0, ...  
                    'WaitEnd', 1 ...                    
                   );
    
    %======================================================================
    
    if ~ischar(task) 
        error('Resuming non supported in distribution mode');
    end
    
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
    
    if mod(size(varargin, 2), 2)
        error('Wrong input arguments : the ''property'' ''value'' scheme is not respected.\nIf may be also due to the fact you don''t pass constant parameters in a one element cell.');
    end    
    args = reshape(varargin, 2, size(varargin, 2) / 2);
    for i = 1 : size(args, 2)
        if ischar(args{1, i})
            if isfield(params, args{1, i})
                params.(args{1, i}) = args{2, i};
            end
        else
            error('Expecting a string for argument %d.', 1 + length(parallel_args) + i);
        end
    end   
    
    if params.KeepTmp == 1
        error('No temporary files in distribution mode');
    end
    
    if params.NoLoad == 1 || params.WaitEnd == 0
        error('Postponing loading is not supported in distribution mode');
    end   
      
    %======================================================================
    
    for i = 1 : length(params.ShellVar)
        if numel(params.ShellVar{i}) ~= 2
            error('ShellVar should be a cell of pairs {variable value}');
        end
    end
           
    nargs = length(parallel_args);
    if params.CombineArgs        
        combine_dims = zeros(1, nargs);
        for i = 1 : nargs
            combine_dims(i) = length(parallel_args{i});
        end
        ninst = prod(combine_dims); 
        
        argIDs = 1:length(parallel_args{1});
        for i = 2 : length(parallel_args)            
            newargIDs = kron(1:length(parallel_args{i}), ones(1, size(argIDs, 2)));
            argIDs = repmat(argIDs, 1, length(parallel_args{i}));            
            argIDs = [argIDs; newargIDs];
        end 
        argIDs = argIDs';
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
        
        argIDs = zeros(ninst, nargs);
        for i = 1 : nargs
            if length(parallel_args{i}) > 1
                argIDs(:, i) = (1 : ninst)';
            else
                argIDs(:, i) = 1;
            end
        end
    end   

    if strcmp(task(end-1:end), '.m')
        task = task(1:end-2);
    end
    if task(1) == '@'
        funnargout = nargout;        
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

    if funnargout >= 0 && nargout > funnargout
        error('The function ''%s'', has not enough output arguments.', task);
    end
        
    if nargout > 0
        varargout = cell(1, nargout);
        for i = 1 : nargout    
            varargout{i} = cell(ninst, 1);
        end
    end
       
    try
        matlabpool open            
    catch
    end
    parfor i = 1 : ninst
        args = cell(1, nargs);
        for j = 1 : nargs
            args{j} = parallel_args{j}{argIDs(i, j)};
        end
        
        res = execute_function(task, args, nargout);
        
        for j = 1 : nargout
            varargout{j}{i} = res{j};
        end
    end    
    try
        matlabpool close
    catch
    end
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
