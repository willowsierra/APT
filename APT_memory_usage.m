function [memUsedMb memPeakMb] = APT_memory_usage()
    pid = APT_getpid();
    [~, m] = system(sprintf('cat /proc/%d/status | grep "VmSize" | sed "s/[A-Za-z]*:[^0-9]*\\([0-9]*\\) kB/\\1/"', pid));
    memUsedMb = round(str2double(m) / 1024);
    [~, m] = system(sprintf('cat /proc/%d/status | grep "VmPeak" | sed "s/[A-Za-z]*:[^0-9]*\\([0-9]*\\) kB/\\1/"', pid));    
    memPeakMb = round(str2double(m) / 1024);
    
    if nargout == 0
        fprintf('MemUsed = %d Mo, MemPeak = %d Mo\n', memUsedMb, memPeakMb);
    end
end
