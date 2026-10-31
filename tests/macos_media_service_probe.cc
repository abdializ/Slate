#include <cstdio>
#include <unistd.h>
#include <dlfcn.h>
#include <cerrno>
#include <mach/mach.h>
#include <servers/bootstrap.h>
int main() {
 using Check = int(*)(pid_t,const char*,int,...);
 auto check=reinterpret_cast<Check>(dlsym(RTLD_DEFAULT,"sandbox_check"));
 if(!check) return 2;
 errno=0;
 int sandboxed=check(getpid(),nullptr,0);
 int pip=check(getpid(),"mach-lookup",2,"com.apple.PIPAgent");
 int spki=check(getpid(),"mach-lookup",2,"dev.slate.browser-spki");
 int spks=check(getpid(),"mach-lookup",2,"dev.slate.browser-spks");
 int other=check(getpid(),"mach-lookup",2,"dev.slate.unrelated-service");
 mach_port_t port=MACH_PORT_NULL;
 int lookup=bootstrap_look_up(bootstrap_port,"com.apple.PIPAgent",&port);
 if(port!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),port);
 printf("{\"sandboxed\":%d,\"pip\":%d,\"spki\":%d,\"spks\":%d,\"unrelated\":%d,\"pip_bootstrap\":%d}\n",sandboxed,pip,spki,spks,other,lookup);
}
