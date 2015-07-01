#!/bin/bash
# align-star-se.sh

script_name="align-star-se.sh"
script_ver="2.0.3"

main() {
    # Now in resources/usr/bin
    #echo "* Download and install STAR..."
    #git clone https://github.com/alexdobin/STAR
    #(cd STAR; git checkout tags/STAR_2.4.0k)
    #(cd STAR; make)
    #wget https://github.com/samtools/samtools/archive/0.1.19.tar.gz

    # If available, will print tool versions to stderr and json string to stdout
    versions=''
    if [ -f /usr/bin/tool_versions.py ]; then 
        versions=`tool_versions.py --applet $script_name --appver $script_ver`
    fi

    echo "* Value of reads: '$reads'"
    echo "* Value of star_index: '$star_index'"
    echo "* Value of library_id: '$library_id'"
    echo "* Value of nthreads: '$nthreads'"

    #echo "* Download files..."
    outfile_name=""
    concat=""
    rm -f concat.fq
    for ix in ${!reads[@]}
    do
        file_root=`dx describe "${reads[$ix]}" --name`
        file_root=${file_root%.fastq.gz}
        file_root=${file_root%.fq.gz}
        if [ "${outfile_name}" == "" ]; then
            outfile_name="${file_root}"
        else
            outfile_name="${file_root}_${outfile_name}"
            if [ "${concat}" == "" ]; then
                outfile_name="${outfile_name}_concat" 
                concat="s concatenated as"
            fi
        fi
        echo "* Downloading and concatenating ${file_root}.fq.gz file..."
        dx download "${reads[$ix]}" -o - | gunzip >> concat.fq
    done
    mv concat.fq ${outfile_name}.fq
    echo "* Gzipping file..."
    gzip ${outfile_name}.fq
    echo "* Fastq${concat} file: '${outfile_name}.fq.gz'"
    reads_root=${outfile_name}
    ls -l ${reads_root}.fq.gz 
    bam_root="${reads_root}_star"
    if [ -f /usr/bin/parse_property.py ]; then
        new_root=`parse_property.py -f "'${reads[0]}'" --project "${DX_PROJECT_CONTEXT_ID}" --root_name --quiet`
        if [ "$new_root" != "" ]; then
            bam_root="${new_root}_star_srna"
        fi
    fi
    echo "* Alignments file will be: '${bam_root}_genome.bam' and '${bam_root}_anno.bam'"

    echo "* Downloading and extracting star index archive..."
    dx download "$star_index" -o star_index.tgz
    tar zxvf star_index.tgz
    # unzips into "out/"

    # Fill in your application code here.

    echo "* Set up headers..."
    set -x
    libraryComment="@CO\tLIBID:${library_id}"
    echo -e ${libraryComment} > COfile.txt
    cat out/*_bamCommentLines.txt >> COfile.txt
    echo `cat COfile.txt`
    set +x

    echo "* Map reads..."
    set -x
    STAR --genomeDir out --readFilesIn ${reads_root}.fq.gz                          \
        --readFilesCommand zcat --runThreadN ${nthreads} --genomeLoad NoSharedMemory \
        --outFilterMultimapNmax 20 --alignSJoverhangMin 8 --alignSJDBoverhangMin 1    \
        --outFilterMismatchNmax 999 --outFilterMismatchNoverReadLmax 0.04              \
        --alignIntronMin 20 --alignIntronMax 1000000 --alignMatesGapMax 1000000         \
        --outSAMheaderCommentFile COfile.txt --outSAMheaderHD @HD VN:1.4 SO:coordinate   \
        --outSAMunmapped Within --outFilterType BySJout --outSAMattributes NH HI AS NM MD \
        --outSAMstrandField intronMotif --outSAMtype BAM SortedByCoordinate                \
        --quantMode TranscriptomeSAM --sjdbScore 1 --limitBAMsortRAM 60000000000

    mv Aligned.sortedByCoord.out.bam ${bam_root}_genome.bam
    mv Log.final.out ${bam_root}_Log.final.out
    set +x
    ls -l ${bam_root}_genome.bam

    echo "* Sorting annotation bam..."
    set -x
    cat <( samtools view -H Aligned.toTranscriptome.out.bam ) \
        <( samtools view -@ ${nthreads} Aligned.toTranscriptome.out.bam | sort -S 60G -T ./ ) | \
        samtools view -@ ${nthreads} -bS - > ${bam_root}_anno.bam
    set +x
    ls -l ${bam_root}_anno.bam

    echo "* Prepare metadata..."
    meta=''
    if [ -f /usr/bin/qc_metrics.py ]; then
        meta=`qc_metrics.py -n STAR_log_final -f ${bam_root}_Log.final.out`
    fi

    echo "* Upload results..."
    star_genome_bam=$(dx upload ${bam_root}_genome.bam --details "{ $meta }" --property SW="$versions" --brief)
    star_anno_bam=$(dx upload ${bam_root}_anno.bam     --details "{ $meta }" --property SW="$versions" --brief)
    star_log=$(dx upload ${bam_root}_Log.final.out --property SW="$versions" --brief)

    dx-jobutil-add-output star_genome_bam "$star_genome_bam" --class=file
    dx-jobutil-add-output star_anno_bam "$star_anno_bam" --class=file
    dx-jobutil-add-output star_log "$star_log" --class=file
    dx-jobutil-add-output metadata "$meta" --class=string

    echo "* Finished."
}
