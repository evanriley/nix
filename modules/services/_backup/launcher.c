#include <spawn.h>
#include <stdio.h>
#include <sys/wait.h>

extern char **environ;

int main(int argc, char **argv) {
    argv[0] = "/run/current-system/sw/bin/borgmatic";
    pid_t pid;
    int err = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (err != 0) {
        fprintf(stderr, "borgmatic-launcher: posix_spawn failed: %d\n", err);
        return 1;
    }
    int status;
    if (waitpid(pid, &status, 0) < 0) {
        perror("borgmatic-launcher: waitpid");
        return 1;
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
