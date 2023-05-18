#include <stdio.h>
#include <stdbool.h>
#include <stdbool.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <ctype.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/types.h>
#include <sys/types.h>
#include <sys/types.h>
#include <sys/types.h>

#define JDI_IOCTL_MAGIC  'J'

#define JDI_IOCTL_JDI_LOCK	\
	_IO(JDI_IOCTL_MAGIC, 23)
#define JDI_IOCTL_JDI_UNLOCK	\
	_IO(JDI_IOCTL_MAGIC, 24)

#define NAME "/dev/jpu"
#define THREAD_NUM	2

static int fds[THREAD_NUM];

static void *dev_threads(void *arg)
{
	int index = *(int *)arg;
	int ret = 1;

	int time = 10;

	while (time--) {
		printf("time = %d\n", time);
		ioctl(fds[index], JDI_IOCTL_JDI_LOCK, &ret);
		sleep(5);
		ioctl(fds[index], JDI_IOCTL_JDI_UNLOCK, &ret);
	}
}

static int open_device(void)
{
	int i;
	for (i = 0; i < THREAD_NUM; i++) {
		fds[i] = open(NAME, O_RDWR | O_NONBLOCK, 0);
		if (fds[i] < 0) {
			printf("Open failed in %d\n", i);
			return -1;
		}
	}

	return 0;
}


static void close_device(void)
{
	int i;
	for (i = 0; i< THREAD_NUM; i++)
		if (fds[i])
			close(fds[i]);
}


int main()
{
	int ret =0, i;
	pthread_t tid[THREAD_NUM];
	if (open_device() < 0) {
		return -1;
	}

	for(i = 0; i < THREAD_NUM; i++) {
		ret = pthread_create(&tid[i], NULL, dev_threads, &i);
		if (ret < 0) {
			printf("create failed\n");
			return -1;
		}
	}

	for(i = 0; i < THREAD_NUM; i++) {
		pthread_join(tid[i], (void **)&i);
	}

	close_device();
}
