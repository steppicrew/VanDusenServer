package CascadedCSS;

use strict;
use warnings;

use Data::Dumper;

sub new {
    my $class= shift;
    my $sPath= shift;

    my $self= {
        path => $sPath,
    };
    
    bless $self, $class;
}

sub render {
    my $self= shift;
    
    my $fh;
    open $fh, $self->{path} or return '';
    
    my @css= ({ context => '', properties => [] },);
    my @currentContext= ();
    my $sLine= '';
    my $iLineNum= 0;
    my $sContext= undef;
    my $hVars= {};
    
    my $resolveVar= sub {
        my $match= shift;
        
        my $var_name= $1 if $match=~ /^\$(\w+)$/ || $match=~ /^\$\{(\w+)\}$/;
        
        return $hVars->{$var_name} if $var_name && exists $hVars->{$var_name};
        return $match;
    };
    
    while (my $sOrigLine= <$fh>) {
        $iLineNum++;
        # scan for variable definition
        $hVars->{$1}= $2 if $sOrigLine=~ s/^\s*\$(\w+)\s*\=\s*(.*?)\s*$//;
        # replace inline variables
        $sOrigLine=~ s/(\$\{?\w+\}?)/$resolveVar->($1)/ge;
        $sLine.= $sOrigLine;
        $sLine=~ s/\s+$//;
        $sLine=~ s/\s+/ /g;
        $sLine=~ s/\/\/.*//s;
        while (1) {
            $sLine=~ s/^\s+//;
            last if $sLine eq '';
#print "[$sLine]\n";
            next if $sLine=~ s/\/\*.*?\*\///g;
            
            # opening css
            if ($sLine=~ s/^([\w\*\.\#\:\[\]\(\)\~\=\"\-\,\>\+\s]+?)\s*\{//) {
                push @currentContext, [split /\s*\,\s*/, $1];
                $sContext= $self->_buildContext(@currentContext);
                next;
            }
            # closing css
            if ($sLine=~ s/^\}//) {
                $self->_error("Closing bracket without opening", $sOrigLine, $iLineNum) unless pop @currentContext;
                $sContext= $self->_buildContext(@currentContext);
                next;
            }
            # standard property
            my $re= qr/^([\w\-]+)\s*\:\s*([\w\s\'\"\\\/\(\)\-\+\.\%\#\=\!\,]+)/;
            if ($sLine=~ s/$re\;// || $sLine=~ s/$re\}/\}/) {
                unless (defined $sContext) {
                    $self->_error("Properties '$1: $2' are in no context", $sOrigLine, $iLineNum);
                    next;
                }
                push @css, {context => $sContext, properties => [] } unless $css[-1]->{context} eq $sContext;
                push @{$css[-1]->{properties}}, "$1: $2;";
                next;
            }
            # continue to next line
            last;
        }
    }
    $self->_error("Could not parse file correctly", $sLine, 0) if $sLine;
    
    close $fh;
    
#print Dumper(\%css);
    
    return $self->_render(\@css);
}

sub _buildContext {
    my $self= shift;
    my $aResult= shift;
    my @sContexts= @_;

    return undef unless $aResult;
    
    for my $aSubContexts (@sContexts) {
        $aResult= [ map { my $sAddContext= $_; map { "$_ $sAddContext" } @$aResult } @$aSubContexts ];
    }
    return join ', ', @$aResult;
}

sub _render {
    my $self= shift;
    my @css= @{shift()};
    my $sResult= '';
    for my $block (@css) {
        next unless scalar @{$block->{properties}};
        $sResult.= $block->{context} . ' {';
        $sResult.= join ' ', @{$block->{properties}};
        $sResult.= "}\n";
    }
    return $sResult;
}

sub _error {
    my $self= shift;
    my $sMessage= shift;
    my $sLine= shift;
    my $iLineNum= shift;
    
    print "ERROR: \"$sMessage\" in line $iLineNum:\n  '$sLine'\n";
}

1;
