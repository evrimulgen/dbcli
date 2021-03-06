/*
 * Copyright (C) 2013 Brett Wooldridge
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.zaxxer.nuprocess.linux;

import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;

/**
 * @author Brett Wooldridge
 */
public class LibEpoll {
    static {
        Native.register(Platform.C_LIBRARY_NAME);
    }

    public static native int sigignore(int signal);

    public static native int epoll_create(int size);

    public static native int epoll_ctl(int epfd, int op, int fd, Pointer event);

    // We only ever call this API with maxevents=1.  However, if calling with maxevents > 1,
    // care must be taken to ensure that the "events" Pointer actually points to a
    // contiguous block of memory large enough to handle maxevents number of EpollEvent
    // mappings.
    //
    // EpollEvent would likely need to be updated to add a convenience method that
    // allocates a block of memory and returns an array of EpollEvents mapped into it.  The
    // EpollEvent.getPointer() of the first array element could then be passed to this API.
    public static native int epoll_wait(int epfd, Pointer events, int maxevents, int timeout);

    public static final int SIGPIPE = 13;

    /* from /usr/include/sys/epoll.h */
    public static final int EPOLL_CTL_ADD = 1; /* Add a file descriptor to the interface.  */
    public static final int EPOLL_CTL_DEL = 2; /* Remove a file descriptor from the interface.  */
    public static final int EPOLL_CTL_MOD = 3; /* Change file descriptor epoll_event structure.  */

    public static final int EPOLLIN = 0x001;
    public static final int EPOLLOUT = 0x004;
    public static final int EPOLLERR = 0x008;
    public static final int EPOLLHUP = 0x010;
    public static final int EPOLLRDHUP = 0x2000;
    public static final int EPOLLONESHOT = (1 << 30);
}
