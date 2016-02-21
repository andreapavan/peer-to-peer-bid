-module(main).
-export([join/4, submitJob/4, checkJob/0, checkJob/1, monitorNode/2, cleanDHT/0]).

-include_lib("includes/record_definition.hrl").


% join(Core, Ram, Disk, Price)
% joins the job scheduling network by registering the node
% {Core, Ram, Disk, Price} as integer
join(Core, Ram, Disk, Price)-> 
	% connect to riak
	connect(),
	% register node to riak (status is ready by default)
	node:addNode(node(), "ready", Core, Ram, Disk, Price),
	% register node name as worker
	work:start(),
	io:format("Benvenuto ~p ~n", [node()]).

submitJob(Core, Ram, Disk, JobCost)-> 
	% register a new job to riak (status is ready by default)
	{_, {_, _, JobKey, _, _, _, _}} = job:addJob("ready", node(), Core, Ram, Disk, JobCost),
	% check if there is a node able to run the new job
	checkJob(JobKey).

checkJob() ->
	checkJob(job:getFirstReadyJob()).

checkJob(false) -> 
	io:format("Invalid job ~n");

checkJob(JobKey) ->
	% check if Job is running (not allowed to reassign a working job)
	JobObj = job:getJobDetail(JobKey),

	if JobObj#job_info.owner /= node() ->
		io:format("You're not the owner of this job ~n", []);
	JobObj#job_info.status == "running" ->
		io:format("The job is already running ~n", []);
	JobObj#job_info.status == "completed" ->
		io:format("The job is already completed ~n", []);
	true ->
		% check if there is a node able to run an existing job
		Node = policy:computeWorker(JobKey),
		if Node /= null ->
			monitorNode(Node#node_info.key, JobKey),
			startJob(Node, JobKey);
		true ->
			io:format("Nessun nodo attulmente disponibile ~nRiprova piu tardi jobKey: ~p~n", [JobKey]),
			JobKey
		end
		
	end.
	

	

monitorNode(Node, JobKey)->
	% Spawn a new process to receive the message from monitoring
	spawn(fun()->
		erlang:monitor_node(Node, true),
		% receive messages
		receive
			% if node is down ...
			{nodedown, NodeDown} -> 
				work:sendDownWork(NodeDown, JobKey)
		end
	end).

startJob(Node, JobKey) ->
	io:format("Job iniziato~n", []),
	work:sendStartWork(Node, JobKey).

% cleanDHT()
% cleans the DHT from all the values, used only for DEBUG purposes
cleanDHT() ->
	% connect to riak
	connect(),
	% clean all jobs
	job:cleanJob(),
	% clean all nodes
	node:cleanNode().

connect() ->
	try
		% get extra parameters for riak connection: address and port
		[RiakAddress,RiakPort] = init:get_plain_arguments(),
		{NewPort, _} = string:to_integer(RiakPort),
		% connection to riak node
		riak:start(RiakAddress, NewPort)
	catch
		Exception:Reason -> {caught, Exception, Reason}
	end.
