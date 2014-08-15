classdef whetlab
    % The interface to the Whetlab api.
    % This client allows you to manipulate experiments in Whetlab
    % and interact with the Whetlab server.
    %
    % A name and description for the experiment must be specified.
    % A Whetlab access token must also be provided.
    % The parameters to tune in the experiment are specified by
    % ``parameters``. It should be a ``struct``, where the fields are
    % the parameters (``str``) and values are ``struct`` that
    % provide information about these parameters. Each of these
    % ``struct`` should contain the appropriate keys to properly describe
    % the parameter:
    %
    % * ``'type'``: type of the parameter (default: ``'float'``)
    % * ``'min'``: minimum value of the parameter
    % * ``'max'``: maximum value of the parameter
    % * ``'size'``: size of parameter (default: ``1``)
    % * ``'units'``: units (``str``) in which the parameter is measured
    % * ``'scale'``: scale to use when exploring parameter values (default: ``'linear'``)
    %
    % Outcome should also be a ``struct``, describing the outcome. It
    % should have the fields:
    %
    % * ``'name'``: name (``str``) for the outcome being optimized
    % * ``'type'``: type of the outcome (default: ``'float'``)
    %
    % Finally, experiments can be resumed from a previous state.
    % To do so, ``name`` must match a previously created experiment
    % and argument ``resume`` must be set to ``True`` (default is ``False``).
    %
    % :param name: Name of the experiment.
    % :type name: str
    % :param description: Description of the experiment.
    % :type description: str
    % :param access_token: Access token for your Whetlab account.
    % :type access_token: str
    % :param parameters: Parameters to be tuned during the experiment.
    % :type parameters: struct
    % :param outcome: Description of the outcome to maximize.
    % :type outcome: struct
    % :param resume: Whether to resume a previously executed experiment. If True, ``parameters`` and ``outcome`` are ignored.
    % :type resume: bool
    % :param force_resume: Whether to create a non-existing experiment if resume is true.
    % :type force_resume: bool
    %
    % A Whetlab experiment instance will have the following variables:
    %
    % :ivar parameters: Parameters to be tuned during the experiment.
    % :type parameters: struct
    % :ivar outcome: Description of the outcome to maximize.
    % :type outcome: struct 
    properties(Access=protected)
        client;
        % Use native java hashtables
        % These are for the client to keep track of things without always 
        % querying the REST server ...
        % ... From result IDs to client parameter values
        ids_to_param_values   = java.util.Hashtable;
        % ... From result IDs to outcome values
        ids_to_outcome_values = java.util.Hashtable;
        % ... From parameters to their 'ids'
        params_to_setting_ids = java.util.Hashtable;
        % All of the parameter values seen thus far
        param_values          = java.util.Hashtable;
        % All of the outcome values seen thus far
        outcome_values        = java.util.Hashtable;
        % The set of result IDs corresponding to suggested jobs that are pending
        pending_ids           = [];
        experiment            = '';
        task                  = '';
        task_description      = '';
        experiment_description= '';
        task_id = -1;
        experiment_id = -1;
        outcome_name = '';
        parameters = struct('name',{}, 'type', {}, 'min', {}, 'max', {}, 'size', {}, 'isOutput', {}, 'units',{},'scale',{});

        % Validation things
        supported_properties = struct('isOutput', {}, 'name', {}, 'min',{}, 'max',{}, 'size',{}, 'scale', {},'units', {}, 'type', {});
        required_properties = struct('min', {}, 'max', {});
        default_values = struct('size',1, 'scale', 'linear', 'units', 'Reals', 'type', 'float');

        INF_PAGE_SIZE = 1000000;

    end

    methods(Static)
        function vars = read_dot_file()
            vars = struct()
            if exist('~/.whetlab', 'file') > 0
                fid = fopen('~/.whetlab')
                C = textscan(fid, '%s=%s', 'CommentStyle', '[')
                fclose(fid)
                for i = 1:length(C{1})
                    vars.(C{1}{i}) = C{2}{i};
                end
            end
        end

        function delete_experiment(access_token, name)
            %
            % Delete the experiment with the given name.  
            %
            % Important, this cancels the experiment and removes all saved results!
            %
            % :param access_token: User access token
            % :type access_token: str
            % :param name: Experiment name
            % :type name: str

            % First make sure the experiment with name exists
            outcome.name = '';
            scientist = whetlab(name, '', access_token, [], outcome, true, false);
            scientist.delete();
        end
    end

    methods

    function self = whetlab(...
             name,...
             description,...
             access_token,...
             parameters,...
             outcome,...
             resume,...
             force_resume)

        assert(usejava('jvm'),'This code requires Java');
        if (nargin == 6)
            resume = true;
        end
        % Force the client to create the experiment if resume is true and it doesn't exist
        if (nargin < 7)
            force_resume = true;
        end

        experiment_id = -1;
        task_id = -1;

        vars = whetlab.read_dot_file()
        if isempty(access_token)
            try
                access_token = vars.access_token
            catch
                error('You must specify your access token in the variable access_token either in the client or in your ~/.whetlab file')
            end
        end
        
        % Make a few obvious asserts
        if (isempty(name) || ~strcmp(class(name), 'char'))
            error('Whetlab:ValueError', 'Name of experiment must be a non-empty string.');
        end

        if (~strcmp(class(description), 'char'))
            error('Whetlab:ValueError', 'Description of experiment must be a string.');
        end

        % Create REST server client
        if isfield(vars, 'api_url')
            hostname = vars.api_url;
        else
            hostname = 'https://api.whetlab.com';
        end
        options = struct('user_agent', 'whetlab_matlab_client',...
            'api_version','api', 'base', hostname);
        options.headers.('Authorization') = ['Bearer ' access_token];
        self.client = whetlab_api_client('', options);

        % For now, we support one task per experiment, and the name and description of the task
        % is the same as the experiment's
        self.experiment_description = description;
        self.experiment = name;
        self.task = name;
        self.task_description = description;
        self.outcome_name = outcome.name;

        if resume
            % Try to resume if the experiment exists. If it doesn't exist, we'll create it.
            self.experiment_id = experiment_id;
            self.task_id = task_id;
            try
                self = self.sync_with_server();
                disp(['Resuming experiment: ' self.experiment]);
                return % Successfully resumed
            catch err
                if ~force_resume || ~strcmp(err.identifier, 'Whetlab:ExperimentNotFoundError')
                    rethrow(err);
                end
            end
        end

        if ~strcmp(class(parameters), 'struct') 
            error('Whetlab:ValueError', 'Parameters of experiment must be a structure array.');
        end

        if ~strcmp(class(outcome), 'struct') && ~isempty(fieldnames(outcome))
            error('Whetlab:ValueError', 'Outcome of experiment must be a non-empty struct.');
        end

        if ~isfield(outcome, 'name')
            error('Whetlab:ValueError', 'Argument outcome should have a field called: name.');
        end
        self.outcome_name = outcome.name;

        % Create new experiment
        % Add specification of parameters        
        for i = 1:numel(parameters)
            param = parameters(i);

            if ~isfield(param, 'name')
                error('Whetlab:UnnamedParameterError', 'You must specify a name for each parameter.')
            end

            % Check if all properties are supported
            if strcmp(param.('type'), 'enum')
                error('Whetlab:ValueError', 'Enum types are not supported yet.  Please use integers instead.');
            end

            properties = fieldnames(param);
            for ii = 1:numel(properties)
                if ~isfield(self.supported_properties, properties{ii})
                    error('Whetlab:ValueError', ['Parameter ' param.name ': property ' properties{ii} ' is not supported.']);
                end
            end

            % Check if required properties are present
            properties = fieldnames(self.required_properties);
            for ii = 1:numel(properties)
                if ~isfield(param, properties{ii})
                    error('Whetlab:ValueError', ['Parameter ' param.name ': property ' properties{ii} ' must be defined.']);
                end
            end

            % Add default parameters if not present
            if ~isfield(param,'units'), param.('units') = self.default_values.units; end
            if ~isfield(param,'scale'), param.('scale') = self.default_values.scale; end
            if ~isfield(param,'type'), param.('type') = self.default_values.type; end

            % Check compatibility of properties
            if param.('min') >= param.('max')
                error('Whetlab:ValueError', ['Parameter ' param.name ': min should be smaller than max.']);
            end

            settings(i) = param;

            f = fieldnames(param);
            for j = 1:numel(f)
                self.parameters(i).(f{j}) = param.(f{j});
            end
        end

        % Add the outcome variable
        param = struct('units','Reals', 'scale','linear', 'type','float');
        outcome = self.structUpdate(param, outcome);
        settings(end+1) = self.structUpdate(settings(end), outcome);
        settings(end).name = self.outcome_name;
        settings(end).isOutput = true;
        settings(end).min = -100;
        settings(end).max = 100;
        settings(end).size = 1;        

        expt.name = name;
        expt.description = description;
        expt.settings = settings;
        try
            res = self.client.experiments().create(name, description, settings, struct());
        catch err
            if (resume && ...
                strcmp(err.identifier, 'MATLAB:HttpConection:ConnectionError') && ...
                ~isempty(strfind(err.message, 'Experiment with this User and Name already exists')))
                self = self.sync_with_server();
                return
            else
                % This experiment was just already created - race condition.
                rethrow(err);
            end
        end
        experiment_id = res.body.('id');
        self.experiment_id = experiment_id;
    end % Experiment()

    function self = sync_with_server(self)
        %%
        %% Synchronize the client's internals with the REST server.
        %%

        % Reset internals
        self.ids_to_param_values.clear();
        self.ids_to_outcome_values.clear();
        self.params_to_setting_ids.clear();

        found = false;

        if self.experiment_id < 0
            % Look for experiment and get the ID... search one page at a time
            page = 1;
            more_pages = true;
            while more_pages
                rest_exps = self.client.experiments().get(struct('query',struct('page',page))).body;
            
                % Check if more pages to come
                more_pages = ~isempty(rest_exps.('next'));
                page = page + 1;

                % Find in current page whether we find the experiment we are looking for
                rest_exps = rest_exps.results;                
                for i = 1:numel(rest_exps)
                    expt = rest_exps{i};
                    if (strcmp(expt.('name'),self.experiment) == 1)
                        self.experiment_id = expt.id;
                        found = true;
                        break;
                    end
                end
                if found
                    break;
                end
            end
            if ~found
                error('Whetlab:ExperimentNotFoundError',...
                    'Experiment with name \"%s\" and description \"%s\" not found.',...
                     self.experiment, self.experiment_description);
            end
        else
            res = self.client.experiments().get(struct('query',struct('id',self.experiment_id))).body.('results');
            self.experiment = res{1}.('name');
            self.experiment_description = res{1}.('description');
        end

        % Get settings for this task, to get the parameter and outcome names
        rest_parameters = self.client.settings().get(num2str(self.experiment_id), struct('query', struct('page_size', self.INF_PAGE_SIZE))).body.('results');
        self.parameters = struct;
        for i = 1:numel(rest_parameters)
            param = rest_parameters{i};
            if(param.experiment ~= self.experiment_id); continue; end
            id = param.('id');
            name = param.('name');
            type=param.('type');
            min=param.('min');
            max=param.('max');
            size=param.('size');
            units=param.('units');
            scale=param.('scale');
            isOutput=param.('isOutput');

            self.params_to_setting_ids.put(name, id);

            if isOutput
                self.outcome_name = name;
            else
                self.parameters.(name) = struct('type',type,'min',min,'max',max,...
                             'size', size ,'units', units,'scale', scale);
            end
        end

        % Get results generated so far for this task
        rest_results = self.client.results().get(struct('query',struct('task',self.task_id,'page_size', self.INF_PAGE_SIZE))).body.('results');
        % Construct things needed by client internally, to keep track of
        % all the results
        for i = 1:numel(rest_results)
            res = rest_results{i};
            res_id = res.('id');
            variables = res.('variables');

            % Construct param_values hash and outcome_values
            for j = 1:numel(variables)
                v = variables{j};

                id = v.('id');
                name = v.('name');                
                if isequal(name, self.outcome_name)
                    % Anything that's passed back as a string is assumed to be a
                    % constraint violation.
                    if isstr(v.value)
                        v.value = -inf;
                    end

                    % Don't record the outcome if the experiment is pending
                    if ~isempty(v.value)
                        self.ids_to_outcome_values.put(res_id, v.value);
                    else % Treat NaN as the special indicator that the experiment is pending. We use -INF for constrant violations
                        self.ids_to_outcome_values.put(res_id, nan);
                    end
                else
                    tmp.(v.('name')) = v.('value');
                    self.ids_to_param_values.put(res_id, savejson('',tmp));
                end
            end
        end

        % Make sure that everything worked
        assert(~isempty(self.outcome_name))
        assert(self.experiment_id >= 0)
        assert(self.task_id >= 0)

    end

    function pend = pending(self)
        %%
        %Return the list of jobs which have been suggested, but for which no 
        %result has been provided yet.
        %
        %return: Struct array of parameter values.
        %rtype: struct array
        %%
    
        % Sync with the REST server     
        self.sync_with_server()

        % Find IDs of results with value None and append parameters to returned list
        i = 1;
        ids = self.ids_to_outcome_values.keySet().toArray();
        outcomes = self.ids_to_outcome_values.values().toArray();
        outcomes = arrayfun(@(x)x, outcomes);
        pend = [];
        for j = 1:length(outcomes)
            val = outcomes(j);
            if isnan(val)
                ret(i) = loadjson(self.ids_to_param_values.get(ids(j)));
                i = i + 1;
                pend = ret;
            end
        end
    end % pending()

    function clear_pending(self)
        %%
        %Delete all of the jobs which have been suggested but for which no 
        %result has been provided yet (i.e. pending jobs).
        %%
        jobs = self.pending();
        if ~isempty(jobs)
            self.cancel(jobs);
        end
        self = self.sync_with_server();
    end        
    function next = suggest(self)
        % Suggest a new job.
        % :return: Values to assign to the parameters in the suggested job.
        % :rtype: struct
        self.sync_with_server();

        assert(self.task_id >= 0)
        res = self.client.suggest(num2str(self.task_id)).go(struct());
        res = res.body;
        result_id = res.('id');
        
        % Remember that this job is now assumed to be pending
        self.pending_ids(end+1) = result_id;
        
        % Poll the server for the actual variable values in the suggestion.  
        % Once the Bayesian optimization proposes an
        % experiment, the server will fill these in.
        variables = res.variables;
        while isempty(variables)
            pause(2);
            result = self.client.result(num2str(result_id)).get(struct());
            variables = result.body.variables;
        end
        
        % Put in a nicer format
        next = struct;
        %f = fieldnames(variables);
        for i = 1:numel(variables)
            if ~strcmp(variables{i}.name, self.outcome_name);
                next.(variables{i}.name) = variables{i}.value;
            end
        end        

        % Keep track of id / param_values relationship
        self.ids_to_param_values.put(result_id, savejson('',next));
    end % suggest

    function id = get_id(self, param_values)
        % Return the result ID corresponding to the given ``param_values``.
        % If no result matches, return -1.
        %
        % :param param_values: Values of parameters.
        % :type param_values: struct
        % :return: ID of the corresponding result. If not match, -1 is returned.
        % :rtype: int or -1

        % First sync with the server
        self = self.sync_with_server();

        id = -1;
        keys = self.ids_to_param_values.keySet().toArray;
        for i = 1:numel(keys)
            if isequal(savejson('', param_values), self.ids_to_param_values.get(keys(i)))
                id = keys(i);
                break;
            end
        end
    end % get_id

    function delete(self)
        %%
        % Delete the experiment with the given name and description.  
        %
        % Important, this cancels the experiment and removes all saved results!
        %% 
        res = self.client.experiment(num2str(self.experiment_id)).delete();
        disp('Experiment has been deleted');
    end
    
    function self = update(self, param_values, outcome_val)
        % Update the experiment with the outcome value associated with some parameter values.
        %
        % :param param_values: Values of parameters.
        % :type param_values: struct
        % :param outcome_val: Value of the outcome.
        % :type outcome_val: type defined for outcome
        %

        % Check whether this param_values has a result ID
        result_id = self.get_id(param_values);

        if result_id == -1
            % - Add new results with param_values and outcome_val

            % Create variables for new result
            param_names = self.params_to_setting_ids.keySet().toArray();
            for i = 1:numel(param_names)
                name = param_names(i);
                setting_id = self.params_to_setting_ids.get(name);
                if isfield(param_values, name)
                    value = param_values.(name);
                elseif strcmp(name, self.outcome_name)
                    value = outcome_val;
                    if ~isfinite(outcome_val)
                        % Convert the outcome to a constraint violation if it's not finite
                        % This is needed to send the JSON in a manner that will be parsed
                        % correctly server-side.
                        value = '-infinity'; 
                    end
                else
                    error('InvalidJobError',...
                        'The job specified is invalid');
                end
                variables(i) = struct('setting', setting_id,...
                    'name',name, 'value',value);                
            end
            result.variables = variables;
            result = self.client.results().add(variables, self.task_id, true, '', '', struct());
            result = result.body;
            result.task = self.task_id;
            result_id = result.id;

            self.ids_to_param_values.put(result_id, savejson('',param_values));
        else
            result = self.client.result(num2str(result_id)).get(struct()).body();

            for i = 1:numel(result.variables)
                var = result.variables{i};

                if isequal(var.('name'), self.outcome_name)
                    result.variables{i}.('value') = outcome_val;
                    self.outcome_values.put(result_id, savejson('',var));
                    break % Assume only one outcome per experiment!
                end
            end

            self.param_values.put(result_id, savejson('',result));
            res = self.client.result(num2str(result_id)).replace(...
                result.variables,result.task, result.userProposed,...
                result.description, result.runDate, result.id, struct());

            % Remove this job from the pending list
            self.pending_ids(self.pending_ids == result_id) = [];
        end
        self.ids_to_outcome_values.put(result_id, outcome_val);
    end %update
    
    %% Cancel a job by removing the parameters and result. 
    function self = cancel(self,param_values)
        % Cancel a job, by removing it from the jobs recorded so far in the experiment.
        %
        % :param param_values: Values of the parameters for the job to cancel.
        % :type param_values: struct or struct array
        %
        % Check whether this param_values has a results ID
        for i = 1:numel(param_values)
            id = self.get_id(param_values(i));
            
            if id ~= -1
                self.ids_to_param_values.remove(num2str(id));

                % Delete from internals
                if self.ids_to_outcome_values.containsKey(id)
                    self.ids_to_outcome_values.remove(id);
                end
                
                % Remove this job from the pending list if it's there.
                self.pending_ids(self.pending_ids == id) = [];

                % Delete from server
                res = self.client.result(num2str(id)).delete(struct());
            else
                warning('Did not find experiment with the provided parameters');
            end
        end
    end % cancel
    
    function param_values = best(self)
        %% Return job with best outcome found so far.        
        %%
        %% :return: Parameter values with best outcome.
        %% :rtype: struct

        % Sync with the REST server     
        self = self.sync_with_server();

        % Find ID of result with best outcome
        ids = self.ids_to_outcome_values.keySet().toArray();
        outcomes = self.ids_to_outcome_values.values().toArray();
        outcomes = arrayfun(@(x)x, outcomes);

        [~, ind] = max(outcomes);
        result_id = ids(ind);

        % Get param values that generated this outcome
        result = self.client.result(num2str(result_id)).get(struct()).body;
        for i = 1:numel(result.('variables'))
            v = result.('variables'){i};
            if ~strcmp(v.name, self.outcome_name)
                param_values.(v.name) = v.value;
            end
        end
        
    end % best
        
    function report(self)
        %% Plot a visual report of the progress made so far in the experiment.
        % Sync with the REST server
        self = self.sync_with_server();

        % Report historical progress and experiments assumed pending

        % Get outcome values and put them in order of their IDs,
        % which should be equivalent to chronological order (of suggestion time)
        ids = self.ids_to_outcome_values.keySet().toArray();
        %# convert to MATLAB vector from java
        ids = arrayfun(@(x)x, ids);
        ids = sort(ids);
        
        for i = 1:numel(ids)
            outcome_values(i) = self.ids_to_outcome_values.get(ids(i));
        end
        
        font_size  = 12;
        fig_height = 10/2;
        fig_width  = 16.18/2;
        line_width = 3;
        position   = [0.14 0.14 0.84 0.84];

        set(0, 'DefaultTextInterpreter', 'tex', ...
              'DefaultTextFontName',    'Helvetica', ...
              'DefaultTextFontSize',    font_size, ...
              'DefaultAxesFontSize',    font_size);

        figure(1); clf();
        set(gcf(), 'Units', 'inches', ...
               'Position', [0 0 fig_width fig_height], ...
               'PaperPositionMode', 'auto');
        subplot('Position', position);
        hold on;

        % Plot progression        
        y = outcome_values;
        maxs(1) = y(1);
        for i = 2:numel(y); maxs(i) = max(y(i), maxs(i-1)); end
        best_so_far = maxs;
        plot(1:numel(y),y,'kx', 'LineWidth', line_width);
        plot(1:numel(y),best_so_far,'k', 'LineWidth', line_width);
        xlabel('Experiment ID');
        ylabel(self.outcome_name);
        title('Outcome values progression');
        legend('Outcomes', 'Best so far');

        figure(2); clf();
        % Add a table of experiments
        param_names = cell(self.params_to_setting_ids.keySet().toArray());
        param_names = setdiff(param_names, self.outcome_name);
        param_vals = [];

        for i = 1:numel(ids)
            params = loadjson(self.ids_to_param_values.get(ids(i)));
            for j = 1:numel(param_names)
                row(j) = params.(param_names{j});             
            end
            param_vals = [param_vals; [row, y(i)]];
        end
        param_names{end+1} = self.outcome_name;
        uitable('Data', param_vals, 'ColumnName', param_names);

    end % report
    % Update struct first with new properties from struct second
    function first = structUpdate(self, first, second)
        f = fieldnames(second);
        for i = 1:numel(f)
            first.(f{i}) = second.(f{i});
        end
    end
    end % methods
end