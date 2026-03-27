#!/usr/bin/env python3
"""Generate a stress-test dataset for Metabuli fseeko vs KSeqWrapper comparison.

Creates:
  - 50 FASTA files with varying numbers of sequences (1-20 per file)
  - ~500 total sequences across 20 species
  - Varying sequence lengths (10K-100K bp)
  - Taxonomy files (names.dmp, nodes.dmp, merged.dmp)
  - accession2taxid.tsv
  - fasta_list.txt
"""
import os
import random
import sys

SEED = 42
NUM_FILES = 50
NUM_SPECIES = 20
MIN_SEQS_PER_FILE = 1
MAX_SEQS_PER_FILE = 20
MIN_SEQ_LEN = 10_000
MAX_SEQ_LEN = 100_000
LINE_WIDTH = 80

def generate_sequence(length, rng):
    bases = "ACGT"
    return "".join(rng.choice(bases) for _ in range(length))

def write_fasta(filepath, sequences):
    """Write sequences as [(accession, seq_string), ...]"""
    with open(filepath, "w") as f:
        for acc, seq in sequences:
            f.write(f">{acc}\n")
            for i in range(0, len(seq), LINE_WIDTH):
                f.write(seq[i:i+LINE_WIDTH] + "\n")

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "test/data/stress"
    os.makedirs(os.path.join(outdir, "taxonomy"), exist_ok=True)

    rng = random.Random(SEED)

    # Generate species taxIDs: 2001..2020
    species_ids = list(range(2001, 2001 + NUM_SPECIES))

    # Generate all sequences, distributing across files
    all_accessions = []  # (accession, species_id, file_idx)
    file_sequences = {}  # file_idx -> [(accession, seq_string)]

    acc_counter = 0
    for file_idx in range(NUM_FILES):
        num_seqs = rng.randint(MIN_SEQS_PER_FILE, MAX_SEQS_PER_FILE)
        file_sequences[file_idx] = []
        for _ in range(num_seqs):
            acc = f"STRESS_{acc_counter:04d}"
            species = rng.choice(species_ids)
            seq_len = rng.randint(MIN_SEQ_LEN, MAX_SEQ_LEN)
            seq = generate_sequence(seq_len, rng)
            file_sequences[file_idx].append((acc, seq))
            all_accessions.append((acc, species, file_idx))
            acc_counter += 1

    total_seqs = acc_counter
    total_bp = 0

    # Write FASTA files
    fasta_paths = []
    for file_idx in range(NUM_FILES):
        fname = f"stress_{file_idx:03d}.fasta"
        fpath = os.path.join(outdir, fname)
        write_fasta(fpath, file_sequences[file_idx])
        fasta_paths.append(os.path.abspath(fpath))
        for _, seq in file_sequences[file_idx]:
            total_bp += len(seq)

    # Write fasta_list.txt
    with open(os.path.join(outdir, "fasta_list.txt"), "w") as f:
        for p in fasta_paths:
            f.write(p + "\n")

    # Write accession2taxid.tsv
    with open(os.path.join(outdir, "accession2taxid.tsv"), "w") as f:
        f.write("accession\taccession.version\ttaxid\tgi\n")
        for acc, species, _ in all_accessions:
            f.write(f"{acc}\t{acc}.1\t{species}\t0\n")

    # Write taxonomy files
    # nodes.dmp: root(1) -> species(2001..2020)
    with open(os.path.join(outdir, "taxonomy", "nodes.dmp"), "w") as f:
        f.write("1\t|\t1\t|\tno rank\t|\t8\t|\t0\t|\t1\t|\t0\t|\t0\t|\t0\t|\t0\t|\t0\t|\t0\t|\n")
        for sid in species_ids:
            f.write(f"{sid}\t|\t1\t|\tspecies\t|\t0\t|\t0\t|\t1\t|\t11\t|\t1\t|\t0\t|\t1\t|\t0\t|\t0\t|\n")

    # names.dmp
    with open(os.path.join(outdir, "taxonomy", "names.dmp"), "w") as f:
        f.write("1\t|\troot\t|\t\t|\tscientific name\t|\n")
        for i, sid in enumerate(species_ids):
            f.write(f"{sid}\t|\tStress Species {i+1}\t|\t\t|\tscientific name\t|\n")

    # merged.dmp (empty)
    with open(os.path.join(outdir, "taxonomy", "merged.dmp"), "w") as f:
        pass

    print(f"Generated stress test dataset:")
    print(f"  Files: {NUM_FILES}")
    print(f"  Total sequences: {total_seqs}")
    print(f"  Total bp: {total_bp:,}")
    print(f"  Species: {NUM_SPECIES}")
    print(f"  Output: {os.path.abspath(outdir)}")

if __name__ == "__main__":
    main()
