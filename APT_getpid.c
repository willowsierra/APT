#include <sys/types.h> 
#include <unistd.h>
#include "mex.h"

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
  plhs[0] = mxCreateDoubleScalar((double) getpid());
}
