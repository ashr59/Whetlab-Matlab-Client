% A unit testing suite for the whetlab Matlab client.
% To run, just add whetlab.m to your path and then type 'results = runtests('test_whetlab.m')'
classdef test_whetlab < matlab.unittest.TestCase
	properties
		default_expt_name = 'Matlab test experiment';
		default_access_token = '';  % Read from dotfile
	end

	methods (Test)
		%% We need to be able to delete experiments for most tests to work
		function testCreateDeleteExperiment(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    outcome.name = 'Negative deviance';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true,testCase.default_access_token, false);
		    
			whetlab.delete_experiment(testCase.default_expt_name,testCase.default_access_token)
		end

		function testSuggestUpdateExperiment(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    outcome.name = 'Negative deviance';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true,testCase.default_access_token, false);
		    
		    job = scientist.suggest();
		    scientist.update(job, 12);

		    scientist.cancel(job);

		    job = scientist.suggest();
		    scientist.update(job, 6.7);

		end

		function testPendingDifferentExperiment(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    outcome.name = 'Negative deviance';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true,testCase.default_access_token, false);
		    
		    job = scientist.suggest();
		    job2 = scientist.suggest();
		    testCase.verifyFalse(isequaln(job, job2));
		end

		function testLargerSizes(testCase)
			size1 = randi([1 10], 1);
			size2 = randi([1 10], 1);
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size', size1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size', size2, 'isOutput',false);
		    outcome.name = 'Negative deviance';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true,testCase.default_access_token, false);
		    
		    job = scientist.suggest();
		    testCase.verifyEqual(numel(job.Lambda), size1);
		    testCase.verifyEqual(numel(job.Alpha), size2);
		    job2 = scientist.suggest();
		    testCase.verifyEqual(numel(job2.Lambda), size1);
		    testCase.verifyEqual(numel(job2.Alpha), size2);
		    testCase.verifyFalse(isequaln(job, job2));
		end

		% Make sure what we pass to the server doesn't get
		% clobbered somehow.
		function testBestExperiment(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    parameters(3) = struct('name', 'nwidgets', 'type','integer',...
		        'min',1,'max',100,'size',1, 'isOutput',false);
		    outcome.name = 'Mojo';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'Waaaa',...
		                    parameters,...
		                    outcome, true, testCase.default_access_token, false);
		    
		    for i = 1:9
		    	job(i) = scientist.suggest();
		    end

		    results = randn(9,1);
		    for i = 1:9
		    	scientist.update(job(i), results(i));
		    end

		    [v, best] = max(results);
		    job_best = rmfield(job(best),'result_id_');
		    testCase.verifyTrue(isequaln(job_best, scientist.best()));
		end

		% Make sure what we pass to the server doesn't get
		% clobbered somehow.
		function testGetAllResults(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    parameters(3) = struct('name', 'nwidgets', 'type','integer',...
		        'min',1,'max',100,'size',1, 'isOutput',false);
		    outcome.name = 'Mojo';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'A great description',...
		                    parameters,...
		                    outcome, true, testCase.default_access_token, false);
		    
		    for i = 1:9
		    	job(i) = scientist.suggest();
		    end

		    [jobs, outcomes] = scientist.get_all_results();
		    for i = 1:numel(job)
		    	equal = false;
		    	testCase.verifyTrue(isnan(outcomes{i}));
		    	for j = 1:numel(jobs)
		    		if whetlab.struct_almost_equal(jobs{j}, job(i));
		    			equal = true;
		    			break
		    		end
		    	end
		    	testCase.verifyTrue(equal);
			end

		    results = randn(9,1);
		    for i = 1:9
		    	scientist.update(job(i), results(i));		    	
		    end

		    [jobs, outcomes] = scientist.get_all_results();
		    setdiff([outcomes{:}], results)

		    testCase.verifyTrue(isempty(setdiff([outcomes{:}], results)));
		    [tmp, ia, ib] = intersect([outcomes{:}], results);
		    for i = 1:numel(ia)
		    	testCase.verifyTrue(scientist.struct_almost_equal(jobs{ia(i)}, job(ib(i))));
		    end
		end

		% Test that we can get the id of an experiment sent to the server.
		function testGetId(testCase)
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    parameters(3) = struct('name', 'nwidgets', 'type','integer',...
		        'min',1,'max',100,'size',1, 'isOutput',false);
		    outcome.name = 'Mojo';

		    % Create a new experiment 
		    scientist = whetlab(testCase.default_expt_name,...
		                    'w00t',...
		                    parameters,...
		                    outcome, true, testCase.default_access_token, false);
		    
		    for i = 1:9
		    	job(i) = scientist.suggest();
		    end

		    results = randn(9,1);
		    for i = 1:9
		    	scientist.update(job(i), results(i));
		    end

		    for i = 1:9
		    	testCase.verifyGreaterThan(scientist.get_id(job(i)), 0);
		    end
		end

		function testStructEqual(testCase)
			a = struct();
			a.a = 'foo';
			a.foo = randn();
			a.blah = randn(5);

			b = a;
			b.foo = a.foo + 1e-16;
			testCase.verifyTrue(whetlab.struct_almost_equal(a,b));
		end

		%% Empty experiment names shouldn't work. 
		function testEmptyCreateExperiment(testCase)    
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    outcome.name = 'Negative deviance';

			try
				% Create a new experiment 
				whetlab('',...
	                    'Foo',...
	                    parameters,...
	                    outcome, true, testCase.default_access_token, false);
			catch err
				testCase.verifyTrue(strcmp(err.identifier, 'Whetlab:ValueError'));
			end
		end

		%% Empty experiment names shouldn't work. 
		function testInvalidParameterType(testCase)    
		    parameters(1) = struct('name', 'Lambda', 'type','foot',...
		        'min',1e-4,'max',0.75,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput',false);
		    outcome.name = 'Negative deviance';

			try
				% Create a new experiment 
				whetlab(testCase.default_expt_name,...
	                    'Foo',...
	                    parameters,...
	                    outcome, true, testCase.default_access_token, false);
			catch err
				testCase.verifyTrue(strcmp(err.identifier, 'MATLAB:HttpConection:ConnectionError'));
				testCase.verifySubstring(err.message, 'Type foot not a valid choice');
			end
		end

		%% Empty experiment names shouldn't work. 
		function testMinGreaterThanMax(testCase)    
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',0.75,'max',0.25,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput', false);
		    outcome.name = 'Negative deviance';

			try
				% Create a new experiment 
				whetlab(testCase.default_expt_name,...
	                    'Foo',...
	                    parameters,...
	                    outcome, true, testCase.default_access_token, false);
			catch err
				testCase.verifyTrue(strcmp(err.identifier, 'Whetlab:ValueError'));
				testCase.verifySubstring(err.message, 'min should be smaller than max.');
			end
		end

		%% Min and Max should be finite numbers
		function testMinMaxAreFinite(testCase)
			vals = [nan, inf, -inf];
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',-inf,'max',0.25,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',inf,'size',1, 'isOutput', false);
		    outcome.name = 'Negative deviance';

		    for i = 1:3
		    	parameters(3) = struct('name', 'Phi', 'type','float',...
		        'min',1e-4,'max', vals(i),'size',1, 'isOutput', false);
				try
					% Create a new experiment 
					whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true, testCase.default_access_token, false);
				catch err
					testCase.verifyTrue(strcmp(err.identifier, 'Whetlab:ValueError'));
					testCase.verifySubstring(err.message, 'min and max should be finite.');
				end
		    	parameters(3) = struct('name', 'Phi', 'type','float',...
		        'min',vals(i),'max',0.7,'size',1, 'isOutput', false);
				try
					% Create a new experiment 
					whetlab(testCase.default_expt_name,...
		                    'Foo',...
		                    parameters,...
		                    outcome, true, testCase.default_access_token, false);
				catch err
					testCase.verifyTrue(strcmp(err.identifier, 'Whetlab:ValueError'));
					testCase.verifySubstring(err.message, 'min and max should be finite.');
				end				
			end
		end

 		%% Empty outcome names shouldn't work. 
		function emptyOutcome(testCase)    
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',0.75,'max',1.25,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput', false);
		    outcome.name = '';

			try
				% Create a new experiment 
				whetlab(testCase.default_expt_name,...
	                    'Foo',...
	                    parameters,...
	                    outcome, true, testCase.default_access_token, false);
			catch err
				testCase.verifyTrue(strcmp(err.identifier, 'MATLAB:HttpConection:ConnectionError'));
				testCase.verifySubstring(err.message, 'required');
			end
		end

		%% Empty description should be ok. 
		function emptyDescription(testCase)    
		    parameters(1) = struct('name', 'Lambda', 'type','float',...
		        'min',0.75,'max',1.25,'size',1, 'isOutput',false);
		    parameters(2) = struct('name', 'Alpha', 'type','float',...
		        'min',1e-4,'max',1,'size',1, 'isOutput', false);
		    outcome.name = 'Bleh';

			% Create a new experiment 
			whetlab(testCase.default_expt_name,...
                    '',...
                    parameters,...
                    outcome, true, testCase.default_access_token, false);
		end

		%% Try to create an already existing experiment with result set to false. 
		function testRandomParameters(testCase)
			N = 50;
			nletters = randi([0, 62], N);			
			vals = randn(N,2);
			mins = min(vals,2);
			maxes = max(vals,2);
			alpha = ['a':'z' 'A':'Z'];
			alphanumeric = ['a':'z' 'A':'Z' '0':'9' '_'];
			alphanumeric_punct = ['a':'z' 'A':'Z' '0':'9' '_!.#$%^&*()'];

			for i = 1:50
				name = [alpha(randi([1, length(alpha)])), ...
				   alphanumeric(randi([1, length(alphanumeric)], nletters(i), 1))];
				parameters(i) = struct('name', name, 'type','float',...
		          'min',mins(i),'max',maxes(i),'size',1, 'isOutput',false);
			end
		    outcome.name = 'Majesty';

			% Create a new experiment
			% Description can be any valid ASCII character
			desc = alphanumeric_punct(randi([1, length(alphanumeric_punct)], nletters(i), 1));
			scientist = whetlab(testCase.default_expt_name,...
                    desc,...
                    parameters,...
                    outcome, true, testCase.default_access_token, false);

		    job = scientist.suggest();
		    scientist.update(job, 12);
        end
        
%% Try to create an already existing experiment with result set to false. 
		function testRandomEnumParameters(testCase)
			N = 50;
			nletters = randi([0, 62], N);			
			vals = randn(N,2);
			mins = min(vals,2);
			maxes = max(vals,2);
			alpha = ['a':'z' 'A':'Z'];
			alphanumeric = ['a':'z' 'A':'Z' '0':'9' '_'];
			alphanumeric_punct = ['a':'z' 'A':'Z' '0':'9' '_!.#$%^&*()'];

			for i = 1:50
				name = [alpha(randi([1, length(alpha)])), ...
				   alphanumeric(randi([1, length(alphanumeric)], nletters(i), 1))];
                optone = [alpha(randi([1, length(alpha)])), ...
				   alphanumeric(randi([1, length(alphanumeric)], nletters(i), 1))];
                opttwo = [alpha(randi([1, length(alpha)])), ...
				   alphanumeric(randi([1, length(alphanumeric)], nletters(i), 1))];

				parameters(i) = struct('name', name, 'type','enum',...
		          'options',{{optone, opttwo}}, 'size',1, 'isOutput',false);
			end
		    outcome.name = 'Majesty';

			% Create a new experiment
			% Description can be any valid ASCII character
			desc = alphanumeric_punct(randi([1, length(alphanumeric_punct)], nletters(i), 1));
			scientist = whetlab(testCase.default_expt_name,...
                    desc,...
                    parameters,...
                    outcome, true, testCase.default_access_token, false);

		    job = scientist.suggest();
		    scientist.update(job, 12);
		end        
	end

	methods(TestMethodSetup)
		function setup(testCase)  % do not change function name
			% Make sure the test experiment doesn't exist
		    try
		        whetlab.delete_experiment(testCase.default_expt_name, testCase.default_access_token)
		    catch
		    	% pass
		    end
		end
	end

	methods(TestMethodTeardown)
		function teardown(testCase)  % do not change function name
			% Make sure the test experiment doesn't exist
		    try
		        whetlab.delete_experiment(testCase.default_expt_name, testCase.default_access_token)
		    catch
		    	% pass
		    end
		end
	end
end