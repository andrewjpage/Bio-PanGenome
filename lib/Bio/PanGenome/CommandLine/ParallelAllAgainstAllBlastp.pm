package Bio::PanGenome::CommandLine::ParallelAllAgainstAllBlastp;

# ABSTRACT: Take in a FASTA file of proteins and blast against itself

=head1 SYNOPSIS

Take in a FASTA file of proteins and blast against itself

=cut

use Moose;
use Getopt::Long qw(GetOptionsFromArray);
use Bio::PanGenome::ParallelAllAgainstAllBlast;

has 'args'        => ( is => 'ro', isa => 'ArrayRef', required => 1 );
has 'script_name' => ( is => 'ro', isa => 'Str',      required => 1 );
has 'help'        => ( is => 'rw', isa => 'Bool',     default  => 0 );

has 'fasta_file'       => ( is => 'rw', isa => 'Str' );
has 'output_filename'  => ( is => 'rw', isa => 'Str', default => 'blast_results' );
has 'job_runner'       => ( is => 'rw', isa => 'Str', default => 'LSF' );
has 'makeblastdb_exec' => ( is => 'rw', isa => 'Str', default => 'makeblastdb' );
has 'blastp_exec'      => ( is => 'rw', isa => 'Str', default => 'blastp' );

has '_error_message' => ( is => 'rw', isa => 'Str' );

sub BUILD {
    my ($self) = @_;

    my ( $fasta_files, $output_filename, $job_runner, $makeblastdb_exec, $blastp_exec, $help );

    GetOptionsFromArray(
        $self->args,
        'o|output=s'           => \$output_filename,
        'j|job_runner=s'       => \$job_runner,
        'm|makeblastdb_exec=s' => \$makeblastdb_exec,
        'b|blastp_exec=s'      => \$blastp_exec,
        'h|help'               => \$help,
    );

    $self->output_filename($output_filename)   if ( defined($output_filename) );
    $self->job_runner($job_runner)             if ( defined($job_runner) );
    $self->makeblastdb_exec($makeblastdb_exec) if ( defined($makeblastdb_exec) );
    $self->blastp_exec($blastp_exec)           if ( defined($blastp_exec) );

    if ( @{ $self->args } == 0 ) {
        $self->_error_message("Error: You need to provide a FASTA file");
    }

    for my $filename ( @{ $self->args } ) {
        if ( !-e $filename ) {
            $self->_error_message("Error: Cant access file $filename");
            last;
        }
    }
    $self->fasta_file( $self->args->[0] );

}

sub run {
    my ($self) = @_;

    ( !$self->help ) or die $self->usage_text;
    if ( defined( $self->_error_message ) ) {
        print $self->_error_message . "\n";
        die $self->usage_text;
    }

    my $blast_obj = Bio::PanGenome::ParallelAllAgainstAllBlast->new(
        fasta_file       => $self->fasta_file,
        blast_results_file_name  => $self->output_filename,
        job_runner       => $self->job_runner,
        makeblastdb_exec => $self->makeblastdb_exec,
        blastp_exec      => $self->blastp_exec
    );
    $blast_obj->run();
}

sub usage_text {
    my ($self) = @_;

    return <<USAGE;
    Usage: parallel_all_against_all_blastp [options]
    Take in a FASTA file of proteins and blast against itself
    
    # Take in a FASTA file of proteins and blast against itself
    parallel_all_against_all_blastp example.faa
    
    # Provide an output filename
    parallel_all_against_all_blastp -o blast_results example.faa

    # This help message
    parallel_all_against_all_blastp -h

USAGE
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
