#!/usr/bin/env bash
# =============================================================================
# run_benchmark.sh — Tricolor HPL Benchmarking Script
#
# Tricolor HPC Cluster · CPSC-375 · Trinity College Hartford · April 2026
# Author: Liu Neptali Restrepo Sanabria
#
# Usage:
#   bash run_benchmark.sh [phase]
#
#   phase: 1        — Phase 1 strong scaling only (1, 2, 3 nodes)
#          2        — Phase 2 parameter tuning only
#          all      — Run all phases sequentially (default)
#
# Prerequisites:
#   - HPL compiled at $HPL_BIN (see below)
#   - Passwordless SSH configured between all nodes
#   - NFS mounted at /home/liu/cluster on all nodes
#   - HPL.dat input files in $SCRIPT_DIR
#
# Results are appended to results/benchmark_results.txt with timestamps.
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HPL_BIN="/home/liu/cluster/hpl-2.3/bin/tricolor/xhpl"
RESULTS_DIR="$SCRIPT_DIR/results"
RESULTS_FILE="$RESULTS_DIR/benchmark_results.txt"

NODE1="192.168.1.101"   # araguaney
NODE2="192.168.1.102"   # turpial
NODE3="192.168.1.103"   # orquidea

PHASE="${1:-all}"

# ── Helpers ───────────────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$RESULTS_FILE"
}

separator() {
    echo "================================================================================" \
        | tee -a "$RESULTS_FILE"
}

run_hpl() {
    local label="$1"
    local np="$2"
    local hosts="$3"
    local dat="$4"

    log "Starting: $label"
    log "  Processes : $np"
    log "  Hosts     : $hosts"
    log "  HPL.dat   : $dat"
    separator

    cp "$dat" "$(dirname "$HPL_BIN")/HPL.dat"

    mpirun -np "$np" --host "$hosts" "$HPL_BIN" 2>&1 | tee -a "$RESULTS_FILE"

    separator
    log "Completed: $label"
    echo ""
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
preflight() {
    log "Running pre-flight checks..."

    if [ ! -f "$HPL_BIN" ]; then
        echo "ERROR: xhpl binary not found at $HPL_BIN"
        echo "       Build HPL first: cd hpl-2.3 && make arch=tricolor"
        exit 1
    fi

    for node in "$NODE1" "$NODE2" "$NODE3"; do
        if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "liu@$node" true 2>/dev/null; then
            echo "ERROR: Cannot SSH into $node without password."
            echo "       Run: ssh-copy-id liu@$node"
            exit 1
        fi
    done

    if ! mountpoint -q /home/liu/cluster 2>/dev/null; then
        echo "WARNING: /home/liu/cluster does not appear to be NFS-mounted."
        echo "         Run: sudo mount -t nfs 192.168.1.10:/Users/Liu/cluster /home/liu/cluster"
    fi

    mkdir -p "$RESULTS_DIR"
    log "Pre-flight checks passed."
    separator
}

# ── Phase 1: Strong Scaling ───────────────────────────────────────────────────
phase1() {
    separator
    log "PHASE 1: Strong Scaling Study"
    log "  Fixed: N=40000, NB=232, 4 processes/node"
    log "  Varied: 1 node → 2 nodes → 3 nodes"
    separator

    # 1 Node — P=2, Q=2
    run_hpl \
        "Phase 1 — 1 Node (P=2, Q=2)" \
        4 \
        "${NODE3}:4" \
        "$SCRIPT_DIR/HPL_phase1.dat"

    # 2 Nodes — P=2, Q=4
    run_hpl \
        "Phase 1 — 2 Nodes (P=2, Q=4)" \
        8 \
        "${NODE1}:4,${NODE2}:4" \
        "$SCRIPT_DIR/HPL_phase1.dat"

    # 3 Nodes — P=3, Q=4
    run_hpl \
        "Phase 1 — 3 Nodes (P=3, Q=4)" \
        12 \
        "${NODE1}:4,${NODE2}:4,${NODE3}:4" \
        "$SCRIPT_DIR/HPL_phase1.dat"

    log "PHASE 1 COMPLETE"
}

# ── Phase 2: Parameter Tuning ─────────────────────────────────────────────────
phase2() {
    separator
    log "PHASE 2: Parameter Tuning Study"
    log "  Fixed: 3 nodes"
    log "  Varied: NB (256→384), N (52000→60000), processes/node (8→16)"
    separator

    # Run 2a — 24 processes, NB=256, N=52000
    run_hpl \
        "Phase 2a — 24 proc, NB=256, N=52000 (P=4, Q=6)" \
        24 \
        "${NODE1}:8,${NODE2}:8,${NODE3}:8" \
        "$SCRIPT_DIR/HPL_phase2a.dat"

    # Run 2b — 48 processes, NB sweep (256 and 384), N=60000
    run_hpl \
        "Phase 2b — 48 proc, NB sweep 256+384, N=60000 (P=6, Q=8)" \
        48 \
        "${NODE1}:16,${NODE2}:16,${NODE3}:16" \
        "$SCRIPT_DIR/HPL_phase2b.dat"

    log "PHASE 2 COMPLETE"
}

# ── Main ──────────────────────────────────────────────────────────────────────
separator
log "Tricolor Cluster — HPL Benchmarking Script"
log "Cluster: Araguaney ($NODE1) · Turpial ($NODE2) · Orquidea ($NODE3)"
log "Results will be written to: $RESULTS_FILE"
separator

preflight

case "$PHASE" in
    1)    phase1 ;;
    2)    phase2 ;;
    all)  phase1; phase2 ;;
    *)
        echo "Usage: $0 [1|2|all]"
        exit 1
        ;;
esac

separator
log "All requested benchmark phases completed."
log "Results saved to: $RESULTS_FILE"
separator
