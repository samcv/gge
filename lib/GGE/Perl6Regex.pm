use v6;
use GGE::Match;
use GGE::Exp;
use GGE::OPTable;
use GGE::TreeSpider;

class GGE::Exp::WS is GGE::Exp does Backtracking {
    # XXX: This class should really derive from GGE::Exp::Subrule, but
    #      that class hasn't been implemented yet, so...
    method start($string, $pos is rw, %pad) {
        %pad<from> = $pos;
        if $pos >= $string.chars {
            %pad<mpos> = $pos;
            MATCH
        }
        elsif $pos == 0 || $string.substr($pos, 1) ~~ /\W/
              || $string.substr($pos - 1, 1) ~~ /\W/ {
            while $pos < $string.chars && $string.substr($pos, 1) ~~ /\s/ {
                ++$pos;
            }
            %pad<mpos> = $pos;
            MATCH
        }
        else {
            FAIL
        }
    }

    method backtracked($_: $pos is rw, %pad) {
        $pos = --%pad<mpos>;
        if $pos >= %pad<from> {
            MATCH
        }
        else {
            FAIL
        }
    }
}

class GGE::Perl6Regex {
    has $!regex;

    my &unescape = -> @codes { join '', map { chr(:16($_)) }, @codes };
    my $h-whitespace = unescape <0009 0020 00a0 1680 180e 2000 2001 2002 2003
                                 2004 2005 2006 2007 2008 2008 2009 200a 202f
                                 205f 3000>;
    my $v-whitespace = unescape <000a 000b 000c 000d 0085 2028 2029>;
    my %esclist =
        'h' => $h-whitespace,
        'v' => $v-whitespace,
        'e' => "\e",
        'f' => "\f",
        'r' => "\r",
        't' => "\t",
    ;

    method new($pattern) {
        my $optable = GGE::OPTable.new();
        $optable.newtok('term:',     :precedence('='),
                        :nows, :parsed(&GGE::Perl6Regex::parse_term));
        $optable.newtok('term:#',    :equiv<term:>,
                        :nows, :parsed(&GGE::Perl6Regex::parse_term_ws));
        $optable.newtok('term:\\',   :equiv<term:>,
                        :nows, :parsed(&GGE::Perl6Regex::parse_term_backslash));
        $optable.newtok('term:^',    :equiv<term:>,
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:^^',   :equiv<term:>,
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:$',    :equiv<term:>, # XXX not per PGE
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:$$',   :equiv<term:>,
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:<<',   :equiv<term:>,
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:>>',   :equiv<term:>,
                        :nows, :match(GGE::Exp::Anchor));
        $optable.newtok('term:.',    :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\d',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\D',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\s',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\S',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\w',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\W',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\N',  :equiv<term:>,
                        :nows, :match(GGE::Exp::CCShortcut));
        $optable.newtok('term:\\n',  :equiv<term:>,
                        :nows, :match(GGE::Exp::Newline));
        $optable.newtok('term:<[',   :equiv<term:>,
                        :nows, :parsed(&GGE::Perl6Regex::parse_enumcharclass));
        $optable.newtok('term:<-',   :equiv<term:>,
                        :nows, :parsed(&GGE::Perl6Regex::parse_enumcharclass));
        $optable.newtok("term:'",    :equiv<term:>,
                        :nows, :parsed(&GGE::Perl6Regex::parse_quoted_literal));
        $optable.newtok('term:::',   :equiv<term:>,
                        :nows, :match(GGE::Exp::Cut));
        $optable.newtok('term::::',  :equiv<term:>,
                        :nows, :match(GGE::Exp::Cut));
        $optable.newtok('term:<commit>', :equiv<term:>,
                        :nows, :match(GGE::Exp::Cut));
        $optable.newtok('circumfix:[ ]', :equiv<term:>,
                        :nows, :match(GGE::Exp::Group));
        $optable.newtok('circumfix:( )', :equiv<term:>,
                        :nows, :match(GGE::Exp::CGroup));
        $optable.newtok('postfix:*', :looser<term:>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:+', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:?', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix::', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('postfix:**', :equiv<postfix:*>,
                        :parsed(&GGE::Perl6Regex::parse_quant));
        $optable.newtok('infix:',    :looser<postfix:*>, :assoc<list>,
                        :nows, :match(GGE::Exp::Concat));
        $optable.newtok('infix:&',   :looser<infix:>,
                        :nows, :match(GGE::Exp::Conj));
        $optable.newtok('infix:|',   :looser<infix:&>,
                        :nows, :match(GGE::Exp::Alt));
        $optable.newtok('prefix:|',  :equiv<infix:|>,
                        :nows, :match(GGE::Exp::Alt));
        $optable.newtok('prefix::',  :looser<infix:|>,
                        :parsed(&GGE::Perl6Regex::parse_modifier));
        my $match = $optable.parse($pattern);
        die 'Perl6Regex rule error: can not parse expression'
            if $match.to < $pattern.chars;
        my $expr = $match.hash-access('expr');
        return self.bless(*, :regex(perl6exp($expr, {})));
    }

    method postcircumfix:<( )>($target, :$debug) {
        if $debug {
            say $!regex.structure;
            say '';
        }
        GGE::TreeSpider.new(:$!regex, :$target, :pos(*)).crawl(:$debug);
    }

    sub parse_term($mob) {
        if $mob.target.substr($mob.to, 1) ~~ /\s/ {
            return parse_term_ws($mob);
        }
        my $m = GGE::Exp::Literal.new($mob);
        my $pos = $mob.to;
        my $target = $m.target;
        while $target.substr($pos, 1) ~~ /\w/ {
            ++$pos;
        }
        if $pos - $mob.to > 1 {
            --$pos;
        }
        if $pos == $mob.to {
            return $m;  # i.e. fail
        }
        $m.to = $pos;
        $m;
    }

    sub parse_term_ws($mob) {
        my $m = GGE::Exp::WS.new($mob);
        $m.to = $mob.to;
        # XXX: This is a fix for my lack of understanding of the relation
        #      between $m.from and $m.pos. There is no corresponding
        #      adjustment needed in PGE.
        if $m.to > 0 && $m.target.substr($m.to - 1, 1) eq '#' {
            --$m.to;
        }
        $m.to++ while $m.target.substr($m.to, 1) ~~ /\s/;
        if $m.target.substr($m.to, 1) eq '#' {
            my $delim = "\n";
            $m.to = defined $m.target.index($delim, $m.to)
                    ?? $m.target.index($delim, $m.to) + 1
                    !!  $m.target.chars;
        }
        $m;
    }

    sub p6escapes($mob, :$pos! is copy) {
        my $m = GGE::Match.new($mob);
        my $target = $m.target;
        my $backchar = $target.substr($pos + 1, 1);
        $pos += 2;
        my $isbracketed = $target.substr($pos, 1) eq '[';
        my $base = $backchar eq 'c'|'C' ?? 10
                !! $backchar eq 'o'|'O' ?? 8
                !!                         16;
        my $literal = '';
        $pos += $isbracketed;
        my &readnum = {
            my $decnum = 0;
            while $pos < $target.chars
                  && defined(
                       my $digit = '0123456789abcdef0123456789ABCDEF'\
                          .index($target.substr($pos, 1))) {
                $digit %= 16;
                $decnum *= $base;
                $decnum += $digit;
                ++$pos;
            }
            $literal ~= chr($decnum);
        };
        if $isbracketed {
            repeat {
                ++$pos while $pos < $target.chars
                             && $target.substr($pos, 1) ~~ /\s/;
                readnum();
                ++$pos while $pos < $target.chars
                             && $target.substr($pos, 1) ~~ /\s/;
            } while $target.substr($pos, 1) eq ',' && ++$pos;
            die "Missing close bracket for \\x[...], \\o[...], or \\c[...]"
                if $target.substr($pos, 1) ne ']';
        }
        else {
            readnum();
        }
        $pos += $isbracketed;
        $m.make($literal);
        $m.to = $pos - 1;
        $m;
    }

    sub parse_term_backslash($mob) {
        my $backchar = substr($mob.target, $mob.to, 1);
        my $isnegated = $backchar eq $backchar.uc;
        $backchar .= lc;
        if $backchar eq 'x'|'c'|'o' {
            my $escapes = p6escapes($mob, :pos($mob.to - 1));
            die 'Unable to parse \x, \c, or \o value'
                unless $escapes;
            # XXX: Can optimize here by special-casing on 1-elem charlist.
            #      PGE does this.
            my GGE::Exp $m = $isnegated ?? GGE::Exp::EnumCharList.new($mob)
                                        !! GGE::Exp::Literal.new($mob);
            $m.hash-access('isnegated') = $isnegated;
            $m.make($escapes.ast);
            $m.to = $escapes.to;
            return $m;
        }
        elsif %esclist.exists($backchar) {
            my $charlist = %esclist{$backchar};
            my GGE::Exp $m = GGE::Exp::EnumCharList.new($mob);
            $m.hash-access('isnegated') = $isnegated;
            $m.make($charlist);
            $m.to = $mob.to;
            return $m;
        }
        elsif $backchar ~~ /\w/ {
            die 'Alphanumeric metacharacters are reserved';
        }

        my $m = GGE::Exp::Literal.new($mob);
        $m.make($backchar);
        $m.to = $mob.to + 1;
        return $m;
    }

    sub parse_enumcharclass($mob) {
        my $target = $mob.target;
        my $pos = $mob.to;
        my $key = $mob.hash-access('KEY');
        # This is only correct as long as we don't do subrules.
        if $key ne '<[' {
            ++$pos;
        }
        ++$pos while $target.substr($pos, 1) ~~ /\s/;
        my Str $charlist = '';
        my Bool $isrange = False;
        while True {
            die "perl6regex parse error: Missing close '>' or ']>' in ",
                "enumerated character class"
                if $pos >= $target.chars;
            given my $char = $target.substr($pos, 1) {
                when ']' {
                    last;
                }
                when '.' {
                    continue if $target.substr($pos, 2) ne '..';
                    $pos += 2;
                    ++$pos while $target.substr($pos, 1) ~~ /\s/;
                    $isrange = True;
                    next;
                }
                when '-' {
                    die "perl6regex parse error: Unescaped '-' in charlist ",
                        "(use '..' or '\\-')";
                }
                when '\\' {
                    ++$pos;
                    $char = $target.substr($pos, 1);
                    continue;
                }
                if $isrange {
                    $isrange = False;
                    my $fromchar = $charlist.substr(-1, 1);
                    die 'perl6regex parse error: backwards range ',
                        "$fromchar..$char not allowed"
                        if $fromchar gt $char;
                    $charlist ~= $_ for $fromchar ^.. $char;
                }
                else {
                    $charlist ~= $char;
                }
            }
            ++$pos;
            ++$pos while $target.substr($pos, 1) ~~ /\s/;
        }
        my $term = GGE::Exp::EnumCharList.new($mob);
        $term.make($charlist);
        if $key eq '<-' {
            $term.hash-access('isnegated') = True;
            $term.hash-access('iszerowidth') = True;
            my $subtraction = GGE::Exp::Concat.new($mob);
            my $everything = GGE::Exp::CCShortcut.new($mob);
            $everything.make('.');
            $subtraction[0] = $term;
            $subtraction[1] = $everything;
            $term = $subtraction;
        }
        $term.to = $pos;
        return $term;
    }

    sub parse_quoted_literal($mob) {
        my $m = GGE::Exp::Literal.new($mob);

        my $target = $m.target;
        my $lit = '';
        my $pos = $mob.to;
        until (my $char = $target.substr($pos, 1)) eq q['] {
            if $char eq '\\' {
                ++$pos;
                $char = $target.substr($pos, 1);
            }
            $lit ~= $char;
            ++$pos;
            die "perl6regex parse error: No closing ' in quoted literal"
                if $pos >= $target.chars;
        }
        $m.make($lit);
        $m.to = $pos;
        $m;
    }

    sub parse_quant($mob) {
        my $m = GGE::Exp::Quant.new($mob);

        my $key = $mob.hash-access('KEY');
        my ($mod2, $mod1);
        given $m.target {
            $mod2   = .substr($mob.to, 2);
            $mod1   = .substr($mob.to, 1);
        }

        $m.hash-access('min') = 1;
        if $key eq '*' | '?' {
            $m.hash-access('min') = 0;
        }

        $m.hash-access('max') = 1;
        if $key eq '*' | '+' | '**' {
            $m.hash-access('max') = Inf;
        }

        #   The postfix:<:> operator may bring us here when it's really a
        #   term:<::> term.  So, we check for that here and fail this match
        #   if we really have a cut term.
        if $key eq ':' && $mod1 eq ':' {
            return $m;
        }

        $m.to = $mob.to;
        if $mod2 eq ':?' {
            $m.hash-access('backtrack') = EAGER;
            $m.to += 2;
        }
        elsif $mod2 eq ':!' {
            $m.hash-access('backtrack') = GREEDY;
            $m.to += 2;
        }
        elsif $mod1 eq '?' {
            $m.hash-access('backtrack') = EAGER;
            ++$m.to;
        }
        elsif $mod1 eq '!' {
            $m.hash-access('backtrack') = GREEDY;
            ++$m.to;
        }
        elsif $mod1 eq ':' || $key eq ':' {
            $m.hash-access('backtrack') = NONE;
            ++$m.to;
        }

        if $key eq '**' {
            my $brackets = False;
            if $m.target.substr($m.to, 1) eq '{' {
                $brackets = True;
                ++$m.to;
            }
            # XXX: Need to generalize this into parsing several digits
            $m.hash-access('min') = $m.hash-access('max') = $m.target.substr($m.to, 1);
            ++$m.to;
            if $m.target.substr($m.to, 2) eq '..' {
                $m.to += 2;
                $m.hash-access('max') = $m.target.substr($m.to, 1);
                ++$m.to;
            }
            if $brackets {
                die 'No "}" found'
                    unless $m.target.substr($m.to, 1) eq '}';
                ++$m.to
            }
        }

        $m;
    }

    sub parse_modifier($mob) {
        my $m = GGE::Exp::Modifier.new($mob);
        my $target = $m.target;
        my $pos = $mob.to;
        my $value = 1;
        my $end-of-num-pos = $pos;
        while $target.substr($end-of-num-pos, 1) ~~ /\d/ {
            ++$end-of-num-pos;
        }
        if $end-of-num-pos > $pos {
            $value = $target.substr($pos, $end-of-num-pos - $pos);
            $pos = $end-of-num-pos;
        }
        my $word = ($target.substr($pos) ~~ /^\w+/).Str;
        my $wordchars = $word.chars;
        return $m   # i.e. fail
            unless $wordchars;
        $pos += $wordchars;
        $m.make($value);
        if $target.substr($pos, 1) eq '(' {
            ++$pos;
            my $closing-paren-pos = $target.index(')', $pos);
            $m.make($target.substr($pos, $closing-paren-pos - $pos));
            $pos = $closing-paren-pos + 1;
        }
        $m.hash-access('key') = $word;
        $m.to = $pos;
        $m;
    }

    multi sub perl6exp(GGE::Exp $exp is rw, %pad) {
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Modifier $exp is rw, %pad) {
        my $key = $exp.hash-access('key');
        if $key eq 'i' {
            $key = 'ignorecase';
        }
        if $key eq 's' {
            $key = 'sigspace';
        }
        # RAKUDO: Looks odd with the '// undef', doesn't it? Well, without
        #         it, things blow up badly if we try to inspect the value
        #         of a hash miss.
        my $temp = %pad{$key} // undef;
        %pad{$key} = $exp.ast;
        $exp[0] = perl6exp($exp[0], %pad);
        %pad{$key} = $temp;
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Concat $exp is rw, %pad) {
        my $n = $exp.elems;
        my @old-children = $exp.llist;
        $exp.clear;
        for @old-children -> $old-child {
            my $new-child = perl6exp($old-child, %pad);
            if defined $new-child {
                $exp.push($new-child);
            }
        }
        # XXX: One difference against PGE here:
        #      no subsequent simplification in the case of only 1
        #      remaining element.
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Quant $exp is rw, %pad) {
        $exp[0] = perl6exp($exp[0], %pad);
        $exp.hash-access('backtrack') //= %pad<ratchet> ?? NONE !! GREEDY;
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Alt $exp is rw, %pad) {
        if !defined $exp[1] {
            return perl6exp($exp[0], %pad);
        }
        if $exp[1] ~~ GGE::Exp::WS {
            die 'Perl6Regex rule error: nothing not allowed in alternations';
        }
        $exp[0] = perl6exp($exp[0], %pad);
        $exp[1] = perl6exp($exp[1], %pad);
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Conj $exp is rw, %pad) {
        if $exp[1] ~~ GGE::Exp::Alt && !defined $exp[1][1] {
            die 'Perl6Regex rule error: "&|" not allowed';
        }
        $exp[0] = perl6exp($exp[0], %pad);
        $exp[1] = perl6exp($exp[1], %pad);
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Group $exp is rw, %pad) {
        $exp[0] = perl6exp($exp[0], %pad);
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::CGroup $exp is rw, %pad) {
        $exp[0] = perl6exp($exp[0], %pad);
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Cut $exp is rw, %pad) {
        $exp.hash-access('cutmark') =
               $exp.ast eq '::'  ?? CUT_GROUP
            !! $exp.ast eq ':::' ?? CUT_RULE
            !!                      CUT_MATCH;
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::Literal $exp is rw, %pad) {
        $exp.hash-access('ignorecase') = %pad<ignorecase>;
        return $exp;
    }

    multi sub perl6exp(GGE::Exp::WS $exp is rw, %pad) {
        if %pad<sigspace> {
            # XXX: Should do stuff here. See PGE.
            return $exp;
        }
        else {
            return ();
        }
    }
}
