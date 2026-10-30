there is a problem in feature. now on general feature view appear refrash function is called.
if folder becomes unavailable or someting happens whole app stucks and not responding.
example is shared desks via network, if it is not available application will wait for system respond about it, during that application is broken.
make fetching for folders independent and a kinda back ground process, on view appear show saved variant with loading animation,
during animation folder have to be unavailable. and on refrash end folder becomes available again.
be carefull with threads and actors to keep ui changing in main actor. check if services need to be actor instead of final class.
