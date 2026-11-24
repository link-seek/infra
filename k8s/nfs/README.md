# NFS 共享存储（RWX）

集群唯一的 RWX 来源。首个消费者：Omnara `memory-data`（api/worker/maintenance 三服务共挂）。

## 为什么是 NFS 而不是 Longhorn

- 小节点扛不住：vm-proxy 0.9G 内存，Longhorn 单节点开销就能撑爆；187ms 延迟下副本同步不可用
- 全集群无 open-iscsi，Longhorn 要逐台装
- memory-data 量小（agent 记忆文件），NFSv4 够用

## 拓扑

```
nfs-server（StatefulSet 单副本，privileged，钉主节点，local-path 20G）
  → Service nfs-server.nfs:2049（headless）
    → nfs-provisioner（Deployment，PROVISIONER_NAME=link-seek/nfs-omnara）
      → StorageClass nfs-omnara（Retain，非默认，需显式引用）
```

## 约束

- edge 节点（东京 vm-proxy / 广州）靠 `dedicated=edge:NoSchedule` 天然排除，不加 toleration
- server 单点：主节点挂掉则 RWX 全挂；恢复=主节点恢复。/exports 定时同步 OBS（待办）
- 删 PVC 不删数据（Retain + archiveOnDelete=false）；空间满手动清 `/exports` 下的 `*-pvc-*` 子目录
