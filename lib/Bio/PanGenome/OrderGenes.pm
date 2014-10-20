package Bio::PanGenome::OrderGenes;

# ABSTRACT: Take in GFF files and create a matrix of what genes are beside what other genes

=head1 SYNOPSIS

Take in the analyse groups and create a matrix of what genes are beside what other genes
   use Bio::PanGenome::OrderGenes;
   
   my $obj = Bio::PanGenome::OrderGenes->new(
     analyse_groups_obj => $analyse_groups_obj,
     gff_files => ['file1.gff','file2.gff']
   );
   $obj->groups_to_contigs;

=cut

use Moose;
use Bio::PanGenome::Exceptions;
use Bio::PanGenome::AnalyseGroups;
use Bio::PanGenome::ContigsToGeneIDsFromGFF;
use Graph;
use Graph::Writer::Dot;

has 'gff_files'           => ( is => 'ro', isa => 'ArrayRef',  required => 1 );
has 'analyse_groups_obj'  => ( is => 'ro', isa => 'Bio::PanGenome::AnalyseGroups',  required => 1 );
has 'group_order'         => ( is => 'ro', isa => 'HashRef',  lazy => 1, builder => '_build_group_order');
has 'group_graphs'        => ( is => 'ro', isa => 'Graph',  lazy => 1, builder => '_build_group_graphs');
has 'groups_to_contigs'        => ( is => 'ro', isa => 'HashRef',  lazy => 1, builder => '_build_groups_to_contigs');
has '_groups_to_file_contigs'  => ( is => 'ro', isa => 'ArrayRef',  lazy => 1, builder => '_build__groups_to_file_contigs');

has '_groups'             => ( is => 'ro', isa => 'HashRef',  lazy => 1, builder => '_build_groups');
has 'number_of_files'     => ( is => 'ro', isa => 'Int', lazy => 1, builder => '_build_number_of_files');
has '_groups_qc'          => ( is => 'ro', isa => 'HashRef', default => sub {{}});

has '_percentage_of_largest_weak_threshold'     => ( is => 'ro', isa => 'Num', default => 0.9);

sub _build_number_of_files
{
  my ($self) = @_;
  return @{$self->gff_files};
}

sub _build_groups
{
  my ($self) = @_;
  my %groups;
  for my $group_name (@{$self->analyse_groups_obj->_groups})
  {
    $groups{$group_name}++;
  }
  return \%groups;
}


sub _build__groups_to_file_contigs
{
  my ($self) = @_;
  my @groups_to_contigs;
  my @overlapping_hypothetical_gene_ids;
  
  # Open each GFF file
  for my $filename (@{$self->gff_files})
  {
    my $contigs_to_ids_obj = Bio::PanGenome::ContigsToGeneIDsFromGFF->new(gff_file   => $filename);
    
    # Loop over each contig in the GFF file
    for my $contig_name (keys %{$contigs_to_ids_obj->contig_to_ids})
    {
      my @groups_on_contig;
      # loop over each gene in each contig in the GFF file
      for my $gene_id (@{$contigs_to_ids_obj->contig_to_ids->{$contig_name}})
      {
        # convert to group name
        my $group_name = $self->analyse_groups_obj->_genes_to_groups->{$gene_id};
        next unless(defined($group_name));
        
        if($contigs_to_ids_obj->overlapping_hypothetical_protein_ids->{$gene_id})
        {
          $self->_groups_qc->{$group_name} = 'Hypothetical protein with no hits to refseq/uniprot/clusters/cdd/tigrfams/pfam overlapping another protein with hits';
        }
        push(@groups_on_contig, $group_name);
      }
      push(@groups_to_contigs,\@groups_on_contig);
    }
  }
      
  return \@groups_to_contigs;
  
}

sub _build_group_order
{
  my ($self) = @_;
  my %group_order;
  
  for my $groups_on_contig (@{$self->_groups_to_file_contigs})
  {
    for(my $i = 1; $i < @{$groups_on_contig}; $i++)
    {
      my $group_from = $groups_on_contig->[$i -1];
      my $group_to = $groups_on_contig->[$i];
      $group_order{$group_from}{$group_to}++;
      # TODO: remove because you only need half the matix
      $group_order{$group_to}{$group_from}++;
    }
    if(@{$groups_on_contig} == 1)
    {
       my $group_from = $groups_on_contig->[0];
       my $group_to = $groups_on_contig->[0];
       $group_order{$group_from}{$group_to}++;
    }
  }

  return \%group_order;
}

sub _build_group_graphs
{
  my($self) = @_;
  return Graph->new(undirected => 1);
}


sub _add_groups_to_graph
{
  my($self) = @_;

  for my $current_group (keys %{$self->group_order()})
  {
    for my $group_to (keys %{$self->group_order->{$current_group}})
    {
      my $weight = 1.0/($self->group_order->{$current_group}->{$group_to} );
      $self->group_graphs->add_weighted_edge($current_group,$group_to, $weight);
    }
  }

}

sub write_out_graph_in_dot_format
{
  my($self,$graph) = @_;
  my $writer = Graph::Writer::Dot->new();
  $writer->write_graph($graph, 'graph.dot');
}


sub _reorder_connected_components
{
   my($self, $graph_groups) = @_;
   
   my @ordered_graph_groups;
   
   my @paths_and_weights;
   
   for my $graph_group( @{$graph_groups})
   {
     
     my $graph = Graph->new(undirected => 1);
     my %groups;
     $groups{$_}++ for (@{$graph_group});
     
     my $total_weight =0;
     my $number_of_edges = 0;
     for my $current_group (keys %groups)
     {
       for my $group_to (keys %{$self->group_order->{$current_group}})
       {
         next if(! defined($groups{$group_to}));
         next if($graph->has_edge($group_to,$current_group));
         my $current_weight = $self->group_order->{$current_group}->{$group_to} ;
         $current_weight = $self->number_of_files if($current_weight > $self->number_of_files);
         my $weight = ($self->number_of_files - $current_weight) +1;

         $graph->add_weighted_edge($current_group,$group_to, $weight);
         $total_weight += $weight;
         $number_of_edges++;
       }
     }
     
     my $average_weight ;
     if($number_of_edges <= 0)
     {
       $average_weight = $self->number_of_files;
     }
     else
     {
       $average_weight = $total_weight/$number_of_edges;
     }

     my $minimum_spanning_tree = $graph->minimum_spanning_tree;
     my $dfs_obj = Graph::Traversal::DFS->new($minimum_spanning_tree);
     my @reordered_dfs_groups = $dfs_obj->dfs;

     push(@paths_and_weights, { 
       path           => \@reordered_dfs_groups,
       average_weight => $average_weight 
     });
     
   }
   
   my @ordered_paths_and_weights =  sort { $a->{average_weight} <=> $b->{average_weight} } @paths_and_weights;
   
   @ordered_graph_groups = map { $_->{path}} @ordered_paths_and_weights;
    
   return \@ordered_graph_groups;
}

sub _build_groups_to_contigs
{
  my($self) = @_;
  $self->_add_groups_to_graph;
  $self->write_out_graph_in_dot_format($self->group_graphs);

  my %groups_to_contigs;
  my $counter = 1;
  my $overall_counter = 1 ;
  my $counter_filtered = 1;
  
  # Accessory
  my $accessory_graph = $self->_create_accessory_graph;
  my @group_graphs = $accessory_graph->connected_components();
  my $reordered_graphs = $self->_reorder_connected_components(\@group_graphs);
  
  for my $contig_groups (@{$reordered_graphs})
  {
    my $order_counter = 1;
  
    for my $group_name (@{$contig_groups})
    {
      $groups_to_contigs{$group_name}{accessory_label} = $counter;
      $groups_to_contigs{$group_name}{accessory_order} = $order_counter;
      $groups_to_contigs{$group_name}{'accessory_overall_order'} = $overall_counter;
      $order_counter++;
      $overall_counter++;
    }
    $counter++;
  }
  
  # Core + accessory
  my @group_graphs_all = $self->group_graphs->connected_components();
  my $reordered_graphs_all = $self->_reorder_connected_components(\@group_graphs_all);
  
  $overall_counter = 1;
  $counter = 1;
  $counter_filtered = 1;
  for my $contig_groups (@{$reordered_graphs_all})
  {
    my $order_counter = 1;
  
    for my $group_name (@{$contig_groups})
    {
      $groups_to_contigs{$group_name}{label} = $counter;
      $groups_to_contigs{$group_name}{comment} = '';
      $groups_to_contigs{$group_name}{order} = $order_counter;
      $groups_to_contigs{$group_name}{'core_accessory_overall_order'} = $overall_counter;
      
      if(@{$contig_groups} <= 2)
      {
        $groups_to_contigs{$group_name}{comment} = 'Investigate';
      }
      elsif($self->_groups_qc->{$group_name})
      {
        $groups_to_contigs{$group_name}{comment} = $self->_groups_qc->{$group_name};
      }
      else
      {
        $groups_to_contigs{$group_name}{'core_accessory_overall_order_filtered'} = $counter_filtered;
        $counter_filtered++;
      }
      $order_counter++;
      $overall_counter++;
    }
    $counter++;
  }
  
  $counter_filtered = 1;
  for my $contig_groups (@{$reordered_graphs})
  {    
    for my $group_name (@{$contig_groups})
    {
        if( (!defined($groups_to_contigs{$group_name}{comment}))  ||  (defined($groups_to_contigs{$group_name}{comment}) && $groups_to_contigs{$group_name}{comment} eq '') )
        {
          $groups_to_contigs{$group_name}{'accessory_overall_order_filtered'} = $counter_filtered;
          $counter_filtered++;
        }
    }
  }
  

  return \%groups_to_contigs;
}

sub _create_accessory_graph
{
  my($self) = @_;
  my $graph = Graph->new(undirected => 1);
  
  my %core_groups;
  
  for my $current_group (keys %{$self->group_order()})
  {
    my $sum_of_weights = 0;
    for my $group_to (keys %{$self->group_order->{$current_group}})
    {
      $sum_of_weights += $self->group_order->{$current_group}->{$group_to};
    }
    if($sum_of_weights >= $self->number_of_files )
    {
      $core_groups{$current_group}++;
    }
  }
  
  for my $current_group (keys %{$self->group_order()})
  {
    next if(defined($core_groups{$current_group}));
    for my $group_to (keys %{$self->group_order->{$current_group}})
    {
      next if(defined($core_groups{$group_to}));
      my $weight =  ($self->number_of_files - $self->group_order->{$current_group}->{$group_to}) +1;
      $graph->add_weighted_edge($current_group,$group_to, $weight);
    }
  }
  $self->_remove_weak_edges_from_graph($graph);
  return $graph;
}

sub _remove_weak_edges_from_graph
{
  my($self, $graph) = @_;
  
  for my $current_group (keys %{$self->group_order()})
  {
    next unless($graph->has_vertex($current_group));
    
    my $largest = 0;
    for my $group_to (keys %{$self->group_order->{$current_group}})
    {
      if($largest < $self->group_order->{$current_group}->{$group_to})
      {
        $largest = $self->group_order->{$current_group}->{$group_to};
      }
    }
    my $threshold_link = int($largest*$self->_percentage_of_largest_weak_threshold);
    next if($threshold_link  <= 1);
    
    for my $group_to (keys %{$self->group_order->{$current_group}})
    {
      if($self->group_order->{$current_group}->{$group_to} < $threshold_link  && $graph->has_edge($current_group,$group_to))
      {
        $graph->delete_edge($current_group, $group_to);
      }
    }
  }
  
}




no Moose;
__PACKAGE__->meta->make_immutable;

1;
