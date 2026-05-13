# Tricolor — Distributed HPC Cluster
**CPSC-375 High-Performance Computing. Trinity College Hartford. April 2026**  
**Author:** `
Liu Neptali Restrepo Sanabria 
`liu.restreposanabria@trincoll.edu`

---

## Cluster Overview

| Node | Role | IP Address | CPU | RAM |
|------|------|------------|-----|-----|
| Laptop (macOS) | Head Node | 192.168.1.10 | Apple M1 | 16 GB |
| Araguaney | Compute Node 1 | 192.168.1.101 | Intel i7-10700 | 16 GB |
| Turpial | Compute Node 2 | 192.168.1.102 | Intel i7-10700 | 16 GB |
| Orquidea | Compute Node 3 | 192.168.1.103 | Intel i7-10700 | 16 GB |

All compute nodes run **Ubuntu Server 22.04 LTS**. The head node (macOS) is used
exclusively for SSH-based cluster management. All MPI jobs are launched from within
a compute node, as the macOS OpenMPI installation is incompatible with the Ubuntu
OpenMPI build on the nodes.

---

## Repository Structure

```
tricolor_source/
├── README.md                   # This file: full setup and run guide
├── tricolor_presentation.pdf   # Presentation slides for project
├── tricolor_report.pdf         # Cluster project full report and analysis
├── src/
    ├──hello_mpi.c              # MPI verification programme
    ├──hpl/
      ├──HPL_phase1.dat         # HPL input file for Phase 1 (strong scaling)
      ├──HPL_phase2a.dat        # HPL input file for Phase 2, run 1 (NB=256, N=52000)
      ├──HPL_phase2b.dat        # HPL input file for Phase 2, run 2 (NB sweep, N=60000)
      ├──Make.tricolor          # HPL Makefile configuration for this cluster
      ├── run_benchmark.sh      # HPL benchmarking script (all phases)
```

---

## 1. Prerequisites

All steps in this section are run **on each compute node** during Internet Mode
(DHCP active, campus network connected).

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    openmpi-bin libopenmpi-dev \
    libopenblas-dev libopenblas0 \
    libatlas-base-dev \
    gcc gfortran make \
    nfs-common
```

Verify MPI installation:
```bash
mpirun --version
# Expected: Open MPI 4.1.x
```

---

## 2. Network Configuration

### 2.1 Static IP Assignment

On each compute node, edit `/etc/netplan/00-installer-config.yaml` (or equivalent)
to assign a static IP. Example for Araguaney:

```yaml
network:
  ethernets:
    enp3s0:
      addresses: [192.168.1.101/24]
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8]
  version: 2
```

Apply with:
```bash
sudo netplan apply
```

Repeat for Turpial (`192.168.1.102`) and Orquidea (`192.168.1.103`).

### 2.2 Verify Connectivity

From any node, ping all others:
```bash
ping -c 3 192.168.1.101   # araguaney
ping -c 3 192.168.1.102   # turpial
ping -c 3 192.168.1.103   # orquidea
```

All should return zero packet loss.

---

## 3. Passwordless SSH

Passwordless SSH must be configured in **both directions**: head node → compute
nodes, and between compute nodes themselves (required for MPI inter-node spawning).

### 3.1 From the head node (laptop):
```bash
ssh-keygen -t ed25519        # Accept all defaults
ssh-copy-id liu@192.168.1.101
ssh-copy-id liu@192.168.1.102
ssh-copy-id liu@192.168.1.103
```

### 3.2 From each compute node (repeat on all three):
```bash
ssh-keygen -t ed25519        # Accept all defaults
ssh-copy-id liu@192.168.1.101
ssh-copy-id liu@192.168.1.102
ssh-copy-id liu@192.168.1.103
```

### 3.3 Verify:
```bash
ssh liu@192.168.1.101 hostname   # Should print: araguaney (no password prompt)
ssh liu@192.168.1.102 hostname   # Should print: turpial
ssh liu@192.168.1.103 hostname   # Should print: orquidea
```

---

## 4. NFS Shared Filesystem

The head node (laptop) exports a shared directory. All compute nodes mount it at
`/home/liu/cluster`, making compiled binaries and input files available cluster-wide.

### 4.1 On the head node (macOS):

Add to `/etc/exports`:
```
/Users/Liu/cluster -alldirs -mapall=liu 192.168.1.101 192.168.1.102 192.168.1.103
```

Restart NFS:
```bash
sudo nfsd restart
showmount -e localhost    # Verify the export is listed
```

### 4.2 On each compute node:

```bash
sudo mkdir -p /home/liu/cluster
sudo mount -t nfs 192.168.1.10:/Users/Liu/cluster /home/liu/cluster
```

Make permanent by adding to `/etc/fstab`:
```
192.168.1.10:/Users/Liu/cluster  /home/liu/cluster  nfs  soft,timeo=30,vers=3  0  0
```

> **Note:** `soft` mount semantics with a 3-second timeout (`timeo=30`) are
> critical. Hard mounts will cause the session to hang indefinitely if the NFS
> server becomes temporarily unreachable.

### 4.3 Verify NFS:
```bash
# On head node:
echo "NFS working from head node" > /Users/Liu/cluster/test.txt

# On each compute node:
cat /home/liu/cluster/test.txt    # Should print the message above
```

---

## 5. MPI Verification

### 5.1 Hostname test

SSH into any compute node, then run:
```bash
mpirun -np 3 \
  --host 192.168.1.101:4,192.168.1.102:4,192.168.1.103:4 \
  hostname
```

Expected output (order may vary as MPI does not guarantee rank ordering in output):
```
araguaney
turpial
orquidea
```

### 5.2 Hello World programme

Compile and run `hello_mpi.c` (included in this repository):
```bash
mpicc -o hello_mpi hello_mpi.c
mpirun -np 3 \
  --host 192.168.1.101:1,192.168.1.102:1,192.168.1.103:1 \
  ./hello_mpi
```

Expected output:
```
Hello from rank 0 of 3 on host araguaney
Hello from rank 1 of 3 on host turpial
Hello from rank 2 of 3 on host orquidea
```

This constitutes the live parallel job demonstration: three independent MPI
processes executing concurrently on three physically separate machines,
coordinating via the OpenMPI runtime over the private 1 GbE network.

---

## 6. HPL Benchmark Setup

### 6.1 Download and extract HPL

```bash
curl -O https://www.netlib.org/benchmark/hpl/hpl-2.3.tar.gz
tar xzf hpl-2.3.tar.gz
cd hpl-2.3
```

### 6.2 Copy the Makefile configuration

Copy `Make.tricolor` (included in this repository) into the HPL root:
```bash
cp /path/to/Make.tricolor /home/liu/cluster/hpl-2.3/Make.tricolor
```

### 6.3 Known build issue — patch required

The default `makes/Make.auxil` file contains a malformed compile rule for
`HPL_dlamch.o` that duplicates the compiler name and omits include paths.
Apply the following patch before building:

Open `makes/Make.auxil` and find line ~93:
```makefile
# ORIGINAL (broken):
$(CC) -o $@ -c $(CCNOOPT)  ../HPL_dlamch.c

# REPLACE WITH:
$(CCNOOPT) -o $@ -c $(HPL_DEFS) -I$(INCdir) -I$(INCdir)/$(ARCH) -I$(MPinc)  ../HPL_dlamch.c
```

### 6.4 Build HPL

```bash
cd /home/liu/cluster/hpl-2.3
make arch=tricolor
```

Build time is approximately 2–3 minutes. Ignore `clock skew` warnings because these are
caused by the NFS timestamp difference between macOS and Linux and do not affect
correctness.

Verify the binary exists:
```bash
ls bin/tricolor/xhpl    # Should exist
```

---

## 7. Running the Benchmark

All benchmark runs are scripted in `run_benchmark.sh`. To run all phases:
```bash
cd /home/liu/cluster/hpl-2.3/bin/tricolor
bash /home/liu/cluster/run_benchmark.sh
```

Or run phases individually as described below.

### 7.1 Phase 1 — Strong Scaling (fixed N, varying nodes)

**1 Node:**
```bash
cp /home/liu/cluster/HPL_phase1.dat HPL.dat
mpirun -np 4 --host 192.168.1.103:4 \
  /home/liu/cluster/hpl-2.3/bin/tricolor/xhpl
```

**2 Nodes:**
```bash
mpirun -np 8 --host 192.168.1.101:4,192.168.1.102:4 \
  /home/liu/cluster/hpl-2.3/bin/tricolor/xhpl
```

**3 Nodes:**
```bash
mpirun -np 12 \
  --host 192.168.1.101:4,192.168.1.102:4,192.168.1.103:4 \
  /home/liu/cluster/hpl-2.3/bin/tricolor/xhpl
```

### 7.2 Phase 2 — Parameter Tuning (3 nodes, varying NB and processes)

**Run 2a** (NB=256, N=52000, 24 processes):
```bash
cp /home/liu/cluster/HPL_phase2a.dat HPL.dat
mpirun -np 24 \
  --host 192.168.1.101:8,192.168.1.102:8,192.168.1.103:8 \
  /home/liu/cluster/hpl-2.3/bin/tricolor/xhpl
```

**Run 2b** (NB sweep 256→384, N=60000, 48 processes):
```bash
cp /home/liu/cluster/HPL_phase2b.dat HPL.dat
mpirun -np 48 \
  --host 192.168.1.101:16,192.168.1.102:16,192.168.1.103:16 \
  /home/liu/cluster/hpl-2.3/bin/tricolor/xhpl
```

> **Memory warning:** Do not exceed N=65000 on this cluster. The attempted
> N=70,000 run was aborted with a bus error (signal 7) due to memory exhaustion
> (~13.1 GB/node, exceeding the 16 GB physical limit).

---

## 8. Results Summary

| Phase | Nodes | Proc | N | NB | Time (s) | GFLOPS |
|-------|-------|------|---|----|----------|--------|
| 1 | 1 | 4 | 40,000 | 232 | 348.33 | 122.50 |
| 1 | 2 | 8 | 40,000 | 232 | 232.82 | 183.27 |
| 1 | 3 | 12 | 40,000 | 232 | 183.68 | 232.30 |
| 2 | 3 | 24 | 52,000 | 256 | 399.89 | 234.42 |
| 2 | 3 | 48 | 60,000 | 256 | 658.94 | 218.54 |
| 2 | 3 | 48 | 60,000 | 384 | 595.03 | **242.01** |

Peak performance: **242.01 GFLOPS** — a 97.6% improvement over the single-node baseline.

---

## 9. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `mpirun` hangs indefinitely | Passwordless SSH not configured between nodes | Re-run `ssh-copy-id` between all node pairs |
| `Authorization required` warnings | X11 display forwarding attempt | Run `export DISPLAY=""` before mpirun |
| `Not enough slots` error | `--host` flag defaults to 1 slot per host | Append `:N` to each host (e.g. `192.168.1.101:4`) |
| NFS session freezes | Hard NFS mount semantics | Remount with `soft,timeo=30` in `/etc/fstab` |
| `hpl.h: No such file` during build | Missing `-I` path in `Make.auxil` | Apply the patch described in Section 6.3 |
| Bus error during HPL run | N too large, memory exhausted | Reduce N; keep below 65,000 on this hardware |
| Clock skew warnings during `make` | NFS timestamp mismatch (macOS vs Linux) | Run `find . -name "Make*" \| xargs touch` |

## 10. Acknowledgements

Thank you, Prof. Yoon. The wisdom and knowledge you transmit in every lecture is inspiring and it pushes me one step further.