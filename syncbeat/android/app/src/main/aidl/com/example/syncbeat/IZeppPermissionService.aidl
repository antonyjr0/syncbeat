package com.example.syncbeat;

import android.os.IBinder;

interface IZeppPermissionService {
    void destroy() = 16777114;
    void beginLease(IBinder owner, long timeoutMillis) = 1;
    void restore() = 2;
    boolean pendingRestore() = 3;
}
