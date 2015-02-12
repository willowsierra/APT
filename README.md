# The Awesome Parallel Toolbox

The Awesome Parallel Toolbox provides simple utilities to run your MATLAB code 
in parallel on your local machine or on the cluster in a transparent manner.

If you have any comment or suggestion please email vincent.delaitre@ens.fr

Table of Contents
=================

- <a href="#specific">Have a specific need ?</a>
- <a href="#install">Installation</a>
- <a href="#quickstart">Quick start</a>
- <a href="#examples">Examples and tricks</a>
- <a href="#params">Optional parameters</a>
- <a href="#compilation">Compilation options</a>
- <a href="#config">APT configuration</a>
- <a href="#versions">Version information</a>


<a name="specific"></a>
Have a specific need ?
======================

APT is like iPhone: there's an option for everything. Please check sections 
"Optional parameters" and "Compilation options" for a comprehensive list of 
options. 

Please also refer to section "Examples and tricks" for the following topics:
- <a href="#ex_errors">Looking at errors</a>
- <a href="#ex_maxjobs">Setting the maximum number of jobs</a>
- <a href="#ex_braces">Getting rid of the braces for constant arguments</a>
- <a href="#ex_crossvalid">Cross-validation</a>
- <a href="#ex_projects">Compiling for multiple projects</a>
- <a href="#ex_relaunch">Relaunching a task</a>
- <a href="#ex_postpone">Postponing the loading of results</a>
- <a href="#ex_async">Using APT in a non-blocking way</a>
- <a href="#ex_anonymous">Anonymous functions</a>
- <a href="#ex_missing">Finding missing jobs</a>
- <a href="#ex_cleaning">Cleaning temporary files</a>
- <a href="#ex_info">Job information at runtime</a>
- <a href="#ex_distrib">Distributing APT</a>
- <a href="#ex_coffee">Making Coffee</a>


<a name="install"></a>
Installation
============

To install the Awesome Parallel Toolbox simply follow the following steps :

1. Add the toolbox directory to your Matlab path.

2. Export your SSH key to the clusters so that you don't need to login with a 
password. To do so, you should first install a SSH client:

```
sudo apt-get install openssh-client
```

You should also generate your private/public keys if you haven't done it 
already:

```
$ ssh-keygen -t dsa -b 1024
```

Use the default file to store the key and leave the passphrase empty.
Finally you have to copy your SSH public key on the clusters:

``` 
$ ssh-copy-id -i ~/.ssh/id_dsa.pub meleze
$ ssh-copy-id -i ~/.ssh/id_dsa.pub sequoia
```

Enter you SSH password each time you are asked.

3. Make sure your .bashrc on Meleze and Sequoia contains the following lines:

```
# Source global definitions
if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi
```
   

<a name="quickstart"></a>
Quick start
===========

Before using the Awesome Parallel Toolbox for running code on the clusters, you 
should compile your Matlab code by calling 'APT_compile' from Matlab. Setup your
Matlab path so that all the code you need is accessible and call:

```
>> APT_compile
```

It will package all the .m and .mex files into a stand-alone binary located in 
<APT_PARAMS.temp_dir> (see 'temp_dir' in section "APT configuration").                        
You only have to recompile if the functions you run in parallel have changed.
You don't need to compile if you run your code on your local machine.

Once compilation is complete, you can launch any function in parallel on the 
cluster. For example, let's suppose you have the following function 'foo':

```
>> function [u v] = foo(a, b, c)
>>     u = a + b + c;
>>     v = a * b * c;
>> end
```

If you want to compute 'foo(1, 3, 4)', 'foo(2, 3, 5)' and 'foo(8, 3, 0)' then
simply do:

```
>> [u v] = APT_run('foo', [1 2 8], {3}, [4 5 0]);
```

You will get u = {8; 10; 11} and v = {12; 30; 0}. More generally you can launch 
any function on a set of N arguments. If an argument is the same for all 
function calls you can simply pass it in a single element cell. Otherwise you 
have to pass all the argument instances in a N elements array, cell or 
structure. You can also pass a 2 dimensional cell, array or structure with N 
rows. Each row will be distributed to its corresponding function call. The 
output of APT_run will be a cell with N rows containing the return parameters of
each function calls.

<a name="examples"></a>
Examples and tricks
===================

<a name="ex_errors"></a>
Looking at errors
-----------------

Here <temp_drive> and <temp_dir> refer to the value defined in APT_params.m
<taskID> is the number displayed when calling APT_run.
The directory '<temp_drive>/$USER/<temp_dir>/<taskID>/logs'
contains the output for each jobs. Each report is named 'report_xxx.txt' 
where 'xxx' is the job number (or Matlab instance number if you are running on
local machine). You can use the function APT_show_report to easily visualize a
report:

``` 
>> APT_show_report(taskID, jobID);
```

A script is also available in <temp_drive>/$USER/<temp_dir>.
    
<a name="ex_maxjobs"></a> 
Setting the maximum number of jobs
----------------------------------

The function APT_jn_set allows you to dynamically change the maximum number of
jobs allowed on the clusters:

```
>> APT_jn_set([job_limit], [cluster_id])
```

Called with no argument, it will print the current job limit. Otherwise,
'job_limit' is the allowed maximum number of running jobs. If 'cluster_id' is
not set, it changes the limit for Meleze and Sequoia. If cluster_id is 1 or 2
it changes the limit only for Meleze or Sequoia respectively.  

A script is also available in <temp_drive>/$USER/<temp_dir>.
Here <temp_drive> and <temp_dir> refer to the value defined in APT_params.m
  
<a name="ex_braces"></a>
Getting rid of the braces for constant arguments
------------------------------------------------

Actually if an argument 'x' is the same for all function calls and if 
numel(x) == 1 then you don't have to put the braces. 
The following call would work:

```
>> [u v] = APT_run('foo', [1 2 8], 3, [4 5 0]); % 3 instead of {3}
```

<a name="ex_crossvalid"></a>
Cross-validation
----------------

If the option 'CombineArgs' is activated the input arguments do not have to be N
elements long: they will be combined to form all possible arrangements of the 
arguments:

```
>> [u v] = APT_run('foo', [1 2], 3, [4 5 0], 'CombineArgs', 1);
```

This will return 3x1x2 cells 'u' and 'v' containing foo(1, 3, 4), foo(2, 3, 4),
foo(1, 3, 5), foo(2, 3, 5), foo(1, 3, 0) and foo(2, 3, 0).

<a name="ex_projects"></a>
Compiling for multiple projects
-------------------------------

If you have different projects, you will have to set a name for the compiled 
code. Having a setup script which does it is a good idea:

```
global APT_PARAMS;
if isempty(APT_PARAMS)
  APT_params();
end 

root = fileparts(mfilename('fullpath'));
[~, f] = fileparts(root);
APT_PARAMS.exec_name = f;
```

<a name="ex_relaunch"></a>
Relaunching a task
------------------

If some jobs failed because of some bug or memory issue and if this bug does 
not affect results' correctness of other jobs, you can relaunch failed jobs
by calling 'APT_run' with the task ID as first argument. For example if a task
had ID 123456 and if you want to increase the available memory you can do:

```
>> res = APT_run(123456, 'Memory', 6000);
```

Depending of the value of 'ResumeType' (see section "Optional parameters"),
it will re-launch only crashed jobs or all the non terminated jobs.
  
<a name="ex_postpone"></a>  
Postponing the loading of results
---------------------------------
  
The option 'NoLoad' ask 'APT_run' to not load the results of the jobs. In
that case 'APT_run' returns the TaskID which can be used to load the job
results one by one by calling 'APT_next_result(TaskID)'. It returns the 
JobID and its output arguments. If JobID is empty you have loaded all the
results. For example the following call:

```
>> [u v] = APT_run('foo', {1 2 8}, {3}, {4 5 0});
```

is equivalent to:

```
>> taskID = APT_run('foo', {1 2 8}, {3}, {4 5 0}, 'NoLoad', 1);
>> u = {};
>> v = {};
>> [jobID tmpu tmpv] = APT_next_result(taskID);
>> while ~isempty(jobID)
>>     u{jobID} = tmpu;
>>     v{jobID} = tmpv;
>>     [jobID tmpu tmpv] = APT_next_result(taskID);
>> end
```

Missing/Crashed jobs are skipped so JobID is only garanteed to be increasing.
  
<a name="ex_async"></a>  
Using APT in a non-blocking way
-------------------------------

Set the 'WaitEnd' option to 1 to continue your program while jobs are running.
APT_run will return two arguments [tID, done]. The first argument is the task 
ID needed to resume the task, second argument is 2 if at least a job crashed, 
1 if all jobs are finished and 0 otherwise. For example this code sample runs
3 jobs and peridocally checks if they are finished:

```
[tID, done] = APT_run('@(x)x', 1:3, 'WaitEnd', 0);
tic;
while ~done
 fprintf('Running since %d seconds...\n', floor(toc));
 pause(1);
 [~, done] = APT_run(tID, 'WaitEnd', 0, 'Verbose', 0);
end
result = APT_run(tID, 'Verbose', 0);
fprintf('Terminated !\n');
disp(result);                                       
```

<a name="ex_anonymous"></a>  
Anonymous functions
-------------------

You can use anonymous functions. This is useful if you don't want to create
a specific function for the operation you want to launch in parallel. The 
example below is analog to the call of the function 'foo' above:

```
>> uv = APT_run('@(a, b, c)[a + b + c, a * b * c]', [1 2 8], 3, [4 5 0]);   
```

<a name="ex_missing"></a>
Finding missing jobs
--------------------

It may happen that some jobs terminate without notifying APT (for example when 
jobs are killed because they use too much memory). If you need to find the IDs 
of the non-terminated jobs use the function APT_missing_jobs:

```
>> APT_missing_jobs(taskID);  % taskID is displayed by 'APT_run'
```

A script is also available in <temp_drive>/$USER/<temp_dir>.
Here <temp_drive> and <temp_dir> refer to the value defined in APT_params.m
  
<a name="ex_cleaning"></a>
Cleaning temporary files
------------------------

Here <temp_drive> and <temp_dir> refer to the value defined in APT_params.m
The temporary files associated with the tasks which fail or are launched with 
the 'KeepTmp' option stay in <temp_drive>/$USER/<temp_dir>. If you don't need to 
relaunch or inspect those tasks you can clean the temporary files by using the 
function APT_remove:

```
>> APT_remove()
```

A script is also available in <temp_drive>/$USER/<temp_dir>.

<a name="ex_info"></a>
Job information at runtime
--------------------------

You have access to a global structure named JOB_INFO which has the following
fields:
- JOB_INFO.cluster_id:   0 if the function is running on local machine,    
                         1 if it is running on Meleze and 2 for Sequoia.
                         
- JOB_INFO.user_dir:     This is a directory located on the local node 
                         (or computer if you run on your machine). This
                         directory is designed to store temporary files for 
                         the running task. Each task has its own directory so 
                         that the files do not mix up between tasks.
                         
- JOB_INFO.job_id:       This is the current parameter set number: 'job_id' is 
                         between 1 and N where N is the number of different
                         parameter sets.   
                                                        
<a name="ex_distrib"></a>
Distributing APT
----------------

The function 'APT_run_fake' is provided to facilitate the distribution of your 
code. Just rename 'APT_run_fake.m' into 'APT_run.m', this will transparently run
your function call on the local computer, using the parfor keyword.

<a name="ex_coffee"></a>
Making coffee
-------------

Try:

```  
>> APT_run([], 'Coffee', 1);
```
  
<a name="params"></a>
Optional parameters
===================

The 'APT_run' function has additional optional parameters that you can use in
the traditional Matlab property/value scheme. For example to run 'foo' on local 
machine with 2 Matlab instances:                               

```
>> [u v] = APT_run('foo', {1 2 8}, {3}, {4 5 0}, 'UseCluster', 0, 'NJobs', 2);
```

The available options are:

- 'Coffee' [default: 0]:      If non-zero it makes the coffee.

- 'ClusterID' [default: 0]:   Choice of the cluster. Jobs will be launched on
                              Meleze if set to 1 and Sequoia if set to 2.
                              If set to 0, 'APT_run' will choose the cluster       
                              which is the less busy.

- 'CombineArgs' [default: 0]: If this option is set to a non-zero value,
                              'APT_run' allows you to pass cell arrays of 
                              arbitrary size as arguments. They will be combined
                              to form all possible arrangements of arguments. 
                              The output will be a N-dimensional cell with N the
                              number of non constant arguments.
                              
- 'GroupBy' [default: 0]:     Not available for computation on your local 
                              machine.If non-zero, 'APT_run' will approximately
                              compute 'GroupBy' sets of arguments per job. Use 
                              this parameter to make short jobs a bit longer so
                              that you do not pay too much overhead for starting
                              a job on the cluster.     

- 'HostName' [default: {}]:   Specify nodes which should be used, e.g. use:
                              '{'node017', 'node018', 'node019', 'node020'}' in 
                              conjonction with 'ClusterID' set to 2 to run your 
                              jobs on the Sequoia nodes which have more memory. 
                              Default is set in 'APT_params' and launch the jobs
                              on any node.
                              
- 'KeepTmp' [default: 0]:     If non-zero: do not erase the temporary directory 
                              <temp_drive>/<temp_dir>/<taskID> containing the 
                              .mat results files after the task is completed. It
                              is particulary useful to debug when used in 
                              combination with the 're-launch feature': see 
                              section 'Interacting with jobs: Relaunching task'.                                 

- 'Libs' [default: {}]:       If your program uses additional libraries, you 
                              can add them using this parameters: one path per 
                              cell entry.
                              
- 'Memory' [default: 0]:      When running jobs on the cluster you should
                              specify the amount of memory they need in Mb. They
                              will be allowed to use additional memory (up to
                              1.8Gb on Meleze, 1.2Gb on Sequoia) but will be 
                              killed if they go beyond this limit. Please also 
                              make sure you do not request a lot more memory 
                              than you need because it will prevent other users 
                              to use free slots. If 'Memory' is null, it is set 
                              to the default value of 2Gb for Meleze and 3.8Gb 
                              for Sequoia.
                              
- 'NJobs' [default: 0]:       If non-zero, 'APT_run' will divide your function
                              calls across 'NJobs' jobs on the cluster (or
                              'NJobs' instances of Matlab if you are running
                              on your local machine). If null, 'APT_run' will
                              run one job per argument set (or 
                              as many Matlab instances as your machine's core 
                              number if you are running on local).
                              
- 'NoJVM' [default: 1]:       Remove the use of JVM if non zero (jobs load 
            faster and use less memory).
                              
- 'NoLoad' [default: 0]:      If non-zero: the return values of the function are
                              not loaded. See section 'Postponing the loading of 
                              results' to see how it can be used.

- 'NSlots' [default: 1]:      If your program uses multi-threading, use this
                              parameter to request the proper number of slots.
                              
- 'ResumeType' [default: 0]:  Use 'ResumeType' when you resume a task, see 
                              section "Interacting with jobs": Relaunching task.
                              If 'ResumeType' is 0 it will re-launch only the 
                              jobs which failed, if it is 1 it will re-launch 
                              all the non-terminated jobs.     

- 'ShellVar' [default: {}]:   Use 'ShellVar' to initialize shell variables 
                              before launching your script. It should be a cell
                              of cells containing two strings in the form:
                              {'variable' 'value'}. For example:
                              APT_run(...,'ShellVar',{{'foo' '1'}{'bar' '2'}});

- 'TimeOut' [default: 0]:     If non-zero: wait termination during 'TimeOut'
                              seconds before returning.
                              
- 'UseCluster' [default: 1]:  Set it to 0 to run your code on your local 
                              machine. It will launch several instances of
                              Matlab and distribute your function calls among
                              them. You don't need to compile your code in that
                              case. If non-zero, 'APT_run' will launch your
                              function on the cluster.                              
                              
- 'Verbose' [default: ?]:     Set verbosity level : 0 (quiet), 1 or 2 (maximum 
                              verbosity). Default value is set by APT_params.m.   
                              
- 'WaitEnd' [default: 1]:     The call to APT_run is non-blocking if zero and 
                              blocking otherwise. When APT_run is non-blocking,
                              it returns two arguments [tID, done]. First 
                              argument is the task ID needed to resume the task, 
                              second argument is 2 if at least a job crashed, 1 
                              if all jobs are finished and 0 otherwise.
                             
                              
<a name="compilation"></a>
Compilation options
===================

Compilation may take some time. However you can make it faster by compiling only
few target functions. It won't be possible to run other functions in parallel 
unless you recompile with the default options. To compile for a restricted list
of functions use:

```
>> APT_compile({'function1' 'function2' ...});
```

You can also ignore some path by using the 'Ignore' option:

```
>> APT_compile(..., 'Ignore', {'path/to/ignore', 'other/path/to/ignore'});
```

By default 'APT_compile' force your compiled Matlab code to use one thread. To
remove this limitation use:

```
>> APT_compile(..., 'SingleThread', 0);
```

By default the JVM is not embedded in compiled application. To remove this 
limitation use:

```
>> APT_compile(..., 'NoJVM', 0);
```
  
<a name="config"></a>
APT Configuration
=================

Among the 'APT_run' options, you can set the Awesome Parallel Toolbox default 
settings in the file APT_params.m:

- login:         This is the SSH login you use to connect on the cluster.

                 
- temp_drive:    The path to the drive where 'APT_run' will generate temporary 
                 files to save function arguments and return values. See 
                 'temp_dir' below.

- temp_dir:      'APT_run' will generate temporary files to save function 
                 arguments and return values in this directory. Each call to 
                 'APT_run' generates a unique task ID and the directory 
                 <temp_drive>/<temp_dir>/<taskID> (denoted below as <taskRoot>)
                 is created. Arguments are stored in <taskRoot>/args, return 
                 values in <taskRoot>/res and log reports in <taskRoot>/logs. If
                 all the jobs terminate successfully, <taskRoot> is deleted. In 
                 case of errors (for example if you did not request enough 
                 memory), you can correct them and relaunch the task (see 
                 section "Interacting with jobs"). Check <temp_drive>/<temp_dir>
                 from time to time to delete old task directories which were not
                 removed because of crashed jobs.
                 
- exec_name:     The name for the binary produced by mcc. You can change it 
                 dynamically if you have different projects: by also changing 
                 your path appropriatly you can make compilation faster.

- loc_dir:       This is a directory located on the local node (or computer if 
                 you run on your machine) in /local/<your_login>. This 
                 directory is designed to store temporary files for the running 
                 task. Each function call has its own directory so that the 
                 files do not mix up between tasks. This directory is deleted 
                 when the function returns or fail.                            

- cluster_id:    If non-zero, this will force the use of the designated cluster:
                 1 for Meleze, 2 for Sequoia.

- host_name:     Specify nodes to use on the cluster. Be sure to also specify
                 the cluster ID. See option 'HostName' for more details.    
                 
- force_local:   If non-zero, this will force the use of local computer.
              
- verbose:       Verbosity level: 0 (quiet), 1 or 2 (maximum verbosity).

- default_libs:  If your program always uses additional libraries, you can add
                 them using this setting: one path per cell entry. Those 
                 libraries will be added to the ones you pass using the 
                 APT_run 'Library' option.

- numcores:      Default number of cores used when running on your local 
                 machine. If null it will use all your cores.           


<a name="versions"></a>
Version information
===================

APT 1.4:
   - APT_globals.m was removed.
   - Show maximum memory used intead of average.
   - Options 'HostName' and 'NoJVM' were added.
   - Function 'APT_next_result' was added.
   - Function 'APT_run_fake' was added.
   - Do not launch jobs when queue is full.
   - Minor bug corrections

APT 1.3:
   - MCR is copied on every node. Supports Matlab 2009b, 2010b, 2011a, 2012a.
   - 'CombineArgs' now reshapes output arguments in a cell matrix having same 
     dimensions as input arguments.
   - Compilation can be made faster when compiling for particular files only.
   - 'APT_compile' use single thread and no JVM by default.
   - Options 'NoLoad' and 'ShellVar' were added.
   - Bugfix: memory default was used when resuming a task.   
   - New script APT_missing jobs.sh

APT 1.2:
   - The script APT_clean.sh was changed to APT_remove.sh.
   - New option 'exec_name' in APT_PARAMS. Can be used to deal with multiple
     projects and make compilation faster.
   - New option 'force_local' in APT_PARAMS.
   - When a job crashes with GroupBy greater than one it does not prevent 
     following jobs to be launched.
   - Task with error terminated since one week are automatically removed.
   - Option 'WaitEnd' and 'TimeOut' were added.
   
APT 1.1: 
   - Option 'KeepTmp' was added.
   - The scripts apt_jn_set and apt_show_report were changed to APT_jn_set.sh 
     and APT_show_report.sh.
   - The script APT_clean.sh was added.
   - Bugfix: problems were encountered with Matlab version >= 2010.
   - APT_run supports anonymous functions.
   - APT_run now supports array, matrices and structures as arguments.
   
APT 1.0:
  - Initial release.
