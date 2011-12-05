package FarmBalance;
use Mouse;
our $VERSION = '0.01';

has 'percent' => (
	is=>'rw',
	isa=>'Int',
	required=>1, 
	default=>100
);
#- Input
#- 以下の個数があっている必要がある。
has 'farms' => (
	is=>'rw', 
	isa=>'Int', 
	required=>1
);
has 'stats' => (
	is=>'rw', 
	isa=>'HashRef[Int]', 
	required=>1
);
has 'input' => (
	is=>'rw', 
	isa=>'HashRef[Int]'
);

has 'debug' => (
	is=>'rw', 
	isa=>'Int', 
	default=>0
);
#- Output
has 'effective_farm' => (
	is=>'rw', 
	isa=>'Int'
);
has 'effect_in_farm_max' => (
	is=>'rw', 
	isa=>'Int'
);
has 'debug' => (is=>'rw', isa=>'Int', default=>0);

__PACKAGE__->meta->make_immutable;
no Mouse;

use Data::Dumper;

#- 入力するアイテムが不明な場合それぞれのバランスキーの実績平均を代入する。
sub input_fill_avg {
	my $self = shift;
	foreach my $bkey ( keys %{ $self->{stats} } ) {
		my $arrayref = $self->{stats}->{$bkey};
		my $avg = $self->average($arrayref);
		$self->{input}->{$bkey} = $avg;
	}
}

#- Define Farm Number
sub define_farm {
	my $self = shift;
	#-バルクを考慮して初期化
	$self->{effective_farm} = undef;
	$self->{effect_in_farm_max} = undef;
	# input がない場合 実績平均の数が来るものと仮定。
	if ( ! defined $self->{input} ) {
		$self->input_fill_avg;
	}
	#- 各ノードごとに効果計算
	my $second_farm;	#- 最も効果的なノード (loser);
	for ( my $farm = 0; $farm < $self->{farms}; $farm++ ) {
		my $farm_str = $farm + 1;
		my $effect_in_farm = 0;		#- before とafterの標準偏差の和で計算
		print "NODE: $farm_str\n" if ( $self->{debug} );
		#- ノードごとに効果値を加算。
		foreach my $b_key ( keys %{$self->{input}} ) {
			#- 事前の標準偏差を計算
			my ( $sd_before ) = $self->sd_percent($self->{stats}->{$b_key});
			if ( $self->{debug} ) {
				print <<"EOF";
 $b_key
   before: $self->{stats}->{$b_key}->[$farm] ::sd: $sd_before
EOF
			}
			#- 当該ノードへの登録を仮定して加算
			$self->{stats}->{$b_key}->[$farm] += $self->{input}->{$b_key};
			#- 事後の標準偏差を計算
			my ( $sd_after ) = $self->sd_percent($self->{stats}->{$b_key});
			#- ポイント: 事後の標準偏差と事前の標準偏差の差。 
			#- 数がプラスであり大きい方がいい。
			my $effect = $sd_before - $sd_after; 
			if ( $self->{debug} ) {
				print <<"EOF";
   after: $self->{stats}->{$b_key}->[$farm] ::sd: $sd_after 
   effect: $effect
EOF
			}
			$effect_in_farm += $effect;;
		}
		print " ->TotalEffect: $effect_in_farm\n" if ( $self->{debug} );
		#- 効果の評価。最も良い候補を選ぶ。
		if ( ! defined $self->{effect_in_farm_max} ) {
			$self->change_effective_farm($farm_str, $effect_in_farm);
		} elsif ( $effect_in_farm > $self->{effect_in_farm_max} ) {
			#- これまでの候補ノードを記憶して、後で値を減算
			$second_farm = $self->{effective_farm} - 1;
			$self->change_effective_farm($farm_str, $effect_in_farm, $second_farm);
		}  else {
			#- 負けた場合もとに戻すように減算しないと書き変わってしまう。
			$self->rollback_stat($farm);
		}
	}

}

#- 効果的なノードの交替
sub change_effective_farm {
	my ( $self, $farm_str, $effect_in_farm, $second_farm ) = @_;
	$self->{effect_in_farm_max} = $effect_in_farm;
	$self->{effective_farm} = $farm_str;
	$self->rollback_stat($second_farm) if ( defined $second_farm);
}

#- 仮に上げた数値を減算
sub rollback_stat {
	my ( $self, $farm ) = @_;
	foreach my $bkey ( keys %{ $self->{input} } ) {
		$self->{stats}->{$bkey}->[$farm] -= $self->{input}->{$bkey};
	}
}
#- 標準偏差レポート
sub report {
	my $self = shift;
	my $stats = $self->{stats};
	print "-----------------------------\n";
	###print Dumper($stats);
	print "farm";
	foreach my $key ( keys %$stats ) {
		print "\t$key";
	}
	print "\n";
	for ( my $farm = 0; $farm < $self->{farms}; $farm++ ) {
		print  $farm + 1 . ':';
		foreach my $key ( keys %$stats ) {
			print "\t", $stats->{$key}->[$farm];
		}
		print "\n";
	}
	print "sd";
	my $total_sd = 0;
	foreach my $key ( keys %$stats ) {
		print "\t" , sprintf("%.2f", $self->sd_percent($stats->{$key}));
		$total_sd += $self->sd_percent($stats->{$key});
	}
	print "\n";
	print "SD_Total:\t" . sprintf("%.2f",$total_sd) . "\n";
	print "-----------------------------\n";
	
}


#- 100％での標準偏差を戻す。
sub sd_percent {
	my ( $self, $a_ref ) = @_;
	$a_ref = $self->arrange_array($a_ref);
	return $self->sd($a_ref);
}

#- 総和を100にした配列に変える
sub arrange_array {
	my ( $self, $arrayref)  = @_;
	my $sum = $self->array_val_sum($arrayref);
	my $kei = $self->{'percent'} / $sum;
	my @nums_new = map { $_ * $kei } @{$arrayref};
	return \@nums_new;
}

#- 標準偏差を戻す
sub sd {
	my ( $self, $arrayref )  = @_;
	my $avg = $self->average($arrayref);
	my $ret = 0;
	for  (@{$arrayref}) {
		$ret += ($_ - $avg)**2;
	}
	return ( $ret/($#$arrayref + 1));
}
#- 配列リファレンスから平均値を出す。
sub average {	
	my ( $self, $arrayref)  = @_;
	my $sum = $self->array_val_sum($arrayref);
	return ( $sum / ( $#$arrayref + 1)  );
}
#- 総和を出す
sub array_val_sum {
	my ( $self, $arrayref)  = @_;
	my $sum = 0;
	for (@{$arrayref}) {
		$sum += $_;
	}
	return $sum;
}


1;
__END__

=head1 NAME

FarmBalance -

=head1 SYNOPSIS

  use FarmBalance;

=head1 DESCRIPTION

FarmBalance is

=head1 AUTHOR

DUKKIE E<lt>dukkiedukkie@yahoo.co.jpE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
