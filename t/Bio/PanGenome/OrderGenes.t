#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use File::Slurp;

BEGIN { unshift( @INC, './lib' ) }

BEGIN {
    use Test::Most;
    use_ok('Bio::PanGenome::OrderGenes');
    use Bio::PanGenome::AnalyseGroups;
}

my $analyse_groups = Bio::PanGenome::AnalyseGroups->new(
    fasta_files     => ['t/data/query_1.fa','t/data/query_2.fa','t/data/query_3.fa'],
    groups_filename => 't/data/query_groups'
);

ok(my $obj = Bio::PanGenome::OrderGenes->new(
  analyse_groups_obj => $analyse_groups,
  gff_files   => ['t/data/query_1.gff','t/data/query_2.gff','t/data/query_3.gff'],
),'Initialise order genes object');

ok( $obj->groups_to_contigs, 'create groups to contigs okay');

my %target = ('a' => 1, 'b' => 1, 'c' => 2, 'd' => 1 );
my %query = ('a' => 1, 'c' => 1,'f' => 1);
is( $obj->_number_of_files_in_common(\%target,\%query), 2, 'count number of files in common');

is_deeply($obj->_freq_of_files_in_array_of_groups(['group_1','group_5']), {
          't/data/query_1.fa' => 1,
          't/data/query_3.fa' => 2,
          't/data/query_2.fa' => 1
        },'correctly count the number of files in groups');

done_testing();
