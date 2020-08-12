#! /usr/bin/env nextflow

/*************************************
 Parallel BLAST
 *************************************/


 def helpMessage() {
     log.info """
      Usage:
      The typical command for running the pipeline is as follows:
      nextflow run parallelBLAST.nf --query QUERY.fasta --genome GENOME.fasta -profile local
      nextflow run parallelBLAST.nf --query QUERY.fasta --dbDir "blastDatabaseDirectory" --dbName "blastPrefixName" -profile local

      Mandatory arguments:
       --query                        Query fasta file of sequences you wish to BLAST
       --genome                       Genome from which BLAST databases will be generated
       or
       --query                        Query fasta file of sequences you wish to BLAST
       --dbDir                        BLAST database directory (full path required)
       --dbName                       Prefix name of the BLAST database
       -profile                       Configuration profile to use. Can use multiple (comma separated)
                                      Available: test, condo, ceres, local, nova

       Optional arguments:
       --outdir                       Output directory to place final BLAST output
       --outfmt                       Output format ['6 qseqid sseqid pident length mismatch gapopen qstart qend sstart send evalue bitscore qlen slen frames salltitles qcovs']
       --options                      Additional options for BLAST command [-evalue 1e-3]
       --outfileName                  Prefix name for BLAST output [blastout]
       --threads                      Number of CPUs to use during blast job [16]
       --chunkSize                    Number of fasta records to use when splitting the query fasta file
       --app                          BLAST program to use [blastn;blastp,tblastx,blastx]
       --help                         This usage statement.
     """
 }


 // Show help message
 if (params.help) {
     helpMessage()
     exit 0
 }


Channel
    .fromPath(params.query)
    .splitFasta(by: params.chunkSize, file:true) // this is how you can split a fasta using nextflow's method
    .set { Query_chunks }

process software_check {
  label 'software_check'

  publishDir params.outdir

  output:
    path 'software_check.txt'

  script:
  """
  echo "blastn -version" > software_check.txt
  blastn -version >> software_check.txt

  echo "\nmakeblastdb -version" >> software_check.txt
  makeblastdb -version >> software_check.txt

  echo "\nparallel --version" >> software_check.txt
  parallel --version >> software_check.txt
  """
}



if (params.genome) {

  genomefile = Channel.fromPath( params.genome )  // in order to have the outfilename be from the file name that is placed in the params.genome variable it has to be from a channel.

  process runMakeBlastDB {
    label 'blast'

    input:
    file outname from genomefile  // grabbing the params.genome filename from the genomefile name created above. Below you will see the use of baseName to grab just the basename without the .fasta

    output:
    val true into done_ch  // may be redundant
    val params.genome.take(params.genome.lastIndexOf('.')) into dbName_ch


    script:
    """
    mkdir DB
    makeblastdb -in ${params.genome} -dbtype 'nucl' -out $params.dbDir/${outname.baseName}
    makeblastdb -in ${params.genome} -dbtype 'prot' -out $params.dbDir/${outname.baseName}
    sleep 1
    """

    }


} else {  // this else statement will automatically create the flag channel done_ch which is now required for runBlast process to proceed
  done_ch = Channel.from(true) // this is probably redundant
  dbName_ch = Channel.from(params.dbName)

}

process runBlast {
  label 'blast'

  input:
  path query from Query_chunks
  val flag from done_ch
  val dbName from dbName_ch

  output:
  path params.outfileName into blast_output

  script:
  """
  echo "${params.app}  -num_threads=${params.threads} -db $params.dbDir/$params.dbName -query $query -outfmt $params.outfmt $params.options -out $params.outfileName" > blast.log

  ${params.app}  -num_threads=${params.threads} -db ${params.dbDir}/$dbName -query $query -outfmt $params.outfmt $params.options -out $params.outfileName

  """

}

blast_output  // this is the channel that you want to collect files; this can also be Channel.from('filename')
    .collectFile(name: 'blast_output_combined.txt', storeDir: params.outdir) // this is the command to do the collection into the file named with name: and the directory with storeDir:
    .subscribe { // subscribe apparently gives you a way to print info to stdout during this process.
        println "Entries are saved to file: $it"
    }
