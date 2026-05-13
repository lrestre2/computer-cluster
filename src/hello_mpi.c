/*
 * hello_mpi.c — MPI Verification Programme
 *
 * Tricolor HPC Cluster · CPSC-375 · Trinity College Hartford · April 2026
 * Author: Liu Neptali Restrepo Sanabria
 *
 * Purpose:
 *   Verifies correct MPI installation, SSH key distribution, and NFS
 *   shared filesystem operation as an integrated system. Each MPI rank
 *   reports its rank number, total process count, and host machine name.
 *   This programme constitutes the live parallel job demonstration for
 *   the Tricolor cluster project.
 *
 * Compile:
 *   mpicc -o hello_mpi hello_mpi.c
 *
 * Run (3 nodes, 1 process each):
 *   mpirun -np 3 \
 *     --host 192.168.1.101:1,192.168.1.102:1,192.168.1.103:1 \
 *     ./hello_mpi
 *
 * Expected output (order may vary):
 *   Hello from rank 0 of 3 on host araguaney
 *   Hello from rank 1 of 3 on host turpial
 *   Hello from rank 2 of 3 on host orquidea
 */

#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {

    /* Initialise the MPI execution environment */
    MPI_Init(&argc, &argv);

    /* Retrieve total number of processes in MPI_COMM_WORLD */
    int world_size;
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    /* Retrieve the rank of this process within MPI_COMM_WORLD */
    int world_rank;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);

    /* Retrieve the hostname of the machine this process is running on */
    char hostname[256];
    int hostname_len;
    MPI_Get_processor_name(hostname, &hostname_len);

    /* Each process prints its identity */
    printf("Hello from rank %d of %d on host %s\n",
           world_rank, world_size, hostname);

    /* Finalise the MPI execution environment */
    MPI_Finalize();

    return 0;
}
