use 5.10.1;
use strict;
use warnings;

# Read text from an input file.
my @multiLineText=<STDIN>;
my $text=join "", @multiLineText;

# Gets a text.
# Split text to list of words ignore comments, 
# treat unescape quote ("...") as one word. 
sub split_to_words
{
  my $text=shift;
  my @words;
  while ($text=~m/("(\\.|[^"\\])*"|\/\/[^\n]*(\n|$)|[^\s]+|\n)/g)
  {
    push @words,$& unless $& =~ m/^\/\//; 
  }
  return @words;
}

# Gets a reference to a list of words.
# Turn a lambda define as [ var1 var2 ... var_n | word1 word2 ... ] 
# to the lambda define as [ defvar var_n defvar var_n-1 ... defvar var1 | word1 word2 ... ]
sub normalize_lambda
{
  # Todo: add error message when it finds errors like
  # unbalance square branches or [ | | ] or [ [ | ] ]
  my $words1=shift;
  # current square brackets
  my $bCur=-1;
  # stack with open square brackets 
  my @bStack;
  # lambda with "|" inside
  my %lambda;

  for my $word (@{$words1}) 
    {
      if ($word eq "[") 
      {
        $bCur++;
        push @bStack,$bCur;
        next;
      }
      if ($word eq "]") 
      {
        pop @bStack;
        next;
      }
      if ($word eq "|") 
      {
        $lambda{$bStack[-1]}=1;
      }
    } 

  # Mode 0 for taking words
  # Mode 1 for pushing words into a temporary stack to
  # bring them back in normalize way "defvar word"
  my $mode=0;
  my @varStack;
  my @words2;
  $bCur=-1;
  for my $word (@{$words1})
    {
      if ($mode==1)
      {
        if ($word eq "|")
        {
          for my $var (reverse @varStack)
          {
            push @words2,"defvar";
            push @words2,$var;
          }
          @varStack=();
          $mode=0;
        }
        else
        {
          push @varStack,$word
        }
        next;
      }
   
      if ($word eq "[")
        {
          $bCur++;
          $mode=1 if exists $lambda{$bCur};
        }
      
      push @words2,$word;
    }
  return @words2;
}

my %macros;

# Gets macro name,macro arguments,macro transformation and
# a flag to check if the transformation is in dynamic forth language or in scheme.
# Save the macro in %macros.
sub define_macro
{
  my ($word,$arg_ref,$trans,$expand_flag)=@_;
  $macros{$word}=[$arg_ref,$trans,$expand_flag];
  return;
}

# Gets a macro name and a reference to macro arguments.
# Return the expanded expression of the macro.
sub use_macro
{
  my $word=shift;
  my $arg_ref=shift;
  my $mac=$macros{$word};
  my($arg_ref2,$trans,$expand_flag)=@{$mac};
  my $trans2=$trans;
  for my $i (0..$#{$arg_ref2})
  {
    my $var=$arg_ref2->[$i];
    my $val=$arg_ref->[$i];
    $val=expand($val) unless $expand_flag || $var=~ m/^[A-Z]/;
    # This is a slow way, We can improve it by
    # spliting the text in advance and avoid using regex 
    $trans2=~ s/(\s|^)$var(\s|$)/$1$val$2/g;
  }
  
  return expand($trans2) if $expand_flag;
  
  return $trans2;
}

# Gets a reference to a list of words and 
# a position after the start of the lambda
# Return a text that contain the lambda expression
sub take_lambda {
  my($words,$pos) = @_;
  my $depth=1;
  my @words2=("[");
# assume that $words->[$pos-1] eq "["
  while ($depth>0)
  {
    my $curWord=$words->[$pos];
    push @words2,$curWord;
    $pos++;
    $depth++ if $curWord eq "[";
    $depth-- if $curWord eq "]";
  }
  return (join(" ",@words2),$pos);
}

# Gets a reference to a list of words and 
# a position after the start of a list
# Return a text that contain the list expression
sub take_list {
  my($words,$pos) = @_;
  my $depth=1;
  my @words2=("(");
# Assume that $words->[$pos-1] eq "("
  while ($depth>0)
  {
    my $curWord=$words->[$pos];
    push @words2,$curWord;
    $pos++;
    $depth++ if $curWord eq "("; 
    $depth-- if $curWord eq ")";
  }
  return (join(" ",@words2),$pos);
}

# Shortcuts
my $pop="pop-global-stack";
my $push="push-global-stack";
# Count the number of branches needed to close all the let expression in the input.
my @closeLet;
# Count the number of lambdas that contain the next words.  
my $lambdaDepth=0;

# Get a reference to a list of words and transfer them to scheme.
sub generate_scheme_code
{
  my $words=shift;
  my @words2;
  # Position on @words2
  my $pos=0; 
  my $len=scalar @{$words};
  while ($pos<$len)
  {
    my $curWord=$words->[$pos];
    $pos++;
    if ($curWord eq "[")
    {
      $lambdaDepth++;
      push @closeLet,0;
      push @words2,"($push (lambda () ";
      next;
    }
    if ($curWord eq "]")
    {
      $lambdaDepth--;
      push @words2,")" for 1..$closeLet[-1]; 
      pop @closeLet;
      push @words2,"))";
      next;
    }
    if ($curWord eq "defun")
    {
      my $var=$words->[$pos];
      $pos++;
      if ($lambdaDepth)
      {
        $closeLet[-1]++;
        push @words2,"(let ((dynamic-forth-$var ($pop)))"; 
      }
      else
      {
        push @words2,"(define dynamic-forth-$var ($pop))";
      }
      next;
    }
    if ($curWord eq "defvar")
    {
      my $var=$words->[$pos];
      $pos++;
      if ($lambdaDepth)
      {
        $closeLet[-1]++;
        push @words2,"(let ((dynamic-forth-$var (pop->func)))";
      }
      else
      {
        push @words2,"(define dynamic-forth-$var (pop->func))";
      }
      next;
    }
    if (exists $macros{$curWord})
    {
      my $args=$macros{$curWord}->[0];
      my $argNum=scalar @{$args};
      my @tempArgs;
      if ($argNum>0)
      {
        for my $i (1..$argNum)
        {
          my $tempWord;
          my $curWord=$words->[$pos];
          while ($curWord eq "\n") 
          {
            $pos++;
            $curWord=$words->[$pos];
          }
          $pos++;
          if ($curWord eq "(")
          {
            ($tempWord,$pos)=take_list($words,$pos);
            push @tempArgs,$tempWord;
            next;
          }
          if ($curWord eq "[")
          {
            ($tempWord,$pos)=take_lambda($words,$pos);
            push @tempArgs,$tempWord;
            next;
          }
          push @tempArgs,$curWord;
        }
        push @words2,use_macro($curWord,\@tempArgs);
      }
      else
      {
        push @words2,use_macro($curWord,[]);
      }
      next;
    }
    # const num or text
    if ($curWord=~ m/^-?([0-9]+(\.[0-9]*)?|\.[0-9]+)$/ || 
        $curWord=~ m/^"(\\.|[^"\\])*"$/)
      {
        push @words2,"(push-global-stack $curWord)"; 
        next;
      }
    # default is a variable
    push @words2,"(dynamic-forth-$curWord)";
  }
  return join(" ",@words2);
}

# Get a Dynamic Forth code and generate a Scheme code.
sub compile
{
  my $text=shift;
  my @words=split_to_words $text;
  @words=normalize_lambda \@words;
  return generate_scheme_code \@words;
}

# Compiling without normalize lambda use to expand code inside macros
# It has one disadvantage, It cannot expand lambdas like [ a b | word1 word2 ]
# You should normalize them manualy by [ defvar b defvar a word1 word2 ]
sub expand
{
  my $text=shift;
  my @words=split_to_words $text;
  return generate_scheme_code \@words;
}

# Scheme code to put in the start of the file.
my $scheme_code=<<'END';
(define *global-stack* '())
(define *global-stack-depth* 0)
(define *collect-stack* '())

(define-syntax when
  (syntax-rules ()
    ((_ c true-body ...)
     (if c (begin true-body ...)))))

(define-syntax unless
  (syntax-rules ()
    ((_ c false-body ...)
     (if (not c) (begin false-body ...)))))

(define (pop-global-stack)
   (let ((temp (car *global-stack*)))
     (set! *global-stack* (cdr *global-stack*))
     (set! *global-stack-depth* (- *global-stack-depth* 1))
     (let loop ((p *collect-stack*))
        (when (and (not (null? p)) (> (car p) *global-stack-depth*))
          (set-car! p *global-stack-depth*)
          (loop (cdr p))))
     temp))

(define (push-global-stack x)
  (set! *global-stack-depth* (+ *global-stack-depth* 1))
  (set! *global-stack* (cons x *global-stack*)))

(define (pop->func)
  (let ((temp (pop-global-stack)))
    (lambda () (push-global-stack temp))))

(define-syntax my-if
  (syntax-rules () 
    ((_ c true-body false-body)
     (let ((x c))
       (if (or (not x)
               (null? x)
               (and (number? x) (= x 0)))
           false-body
           true-body)))
    ((_ c true-body)
     (let ((x c))
       (if (not (or (not x)
                    (null? x)
                    (and (number? x) (= x 0))))
           true-body)))))

(define-syntax my-when
  (syntax-rules ()
    ((_ c false-body ...)
     (let ((x c))
       (if (not (or (not x)
                    (null? x)
                    (and (number? x) (= x 0))))
           (begin false-body ...)))))) 

(define-syntax my-unless
  (syntax-rules ()
    ((_ c false-body ...)
     (let ((x c))
       (if (or (not x)
               (null? x)
               (and (number? x) (= x 0)))
           (begin false-body ...))))))

(define-syntax my-with-pop
  (syntax-rules ()
    ((_ (vars ...) body ...)
     (my-with-pop "helper" (vars ...) () body ...))
    ((_ "helper" () (lst ...) body ...)
     (let* ((lst (pop-global-stack)) ...) body ...))
    ((_ "helper" (arg rest ...) (lst ...) body ...)
     (my-with-pop "helper" (rest ...) (arg lst ...) body ...))))

(define (dynamic-forth-my-fun->fun+)
  (my-with-pop (fn)
    (push-global-stack
      (lambda ()
        (call-with-current-continuation
          (lambda (dynamic-forth-return)
            (push-global-stack dynamic-forth-return)
            (fn)))))))

(define (dynamic-forth-rot-up)
  (if (not (or (null? *global-stack*) (null? (cdr *global-stack*))))
      (let ((temp (cdr *global-stack*)))
        (set-cdr! *global-stack* '())
        (let loop ((p temp))
          (if (null? (cdr p))
              (set-cdr! p *global-stack*)
              (loop (cdr p))))
        (set! *global-stack* temp))))

(define (dynamic-forth-rot-down)
  (if (not (or (null? *global-stack*) (null? (cdr *global-stack*))))
      (let loop ((p *global-stack*))
        (if (null? (cddr p))
            (let ((result (cdr p))) 
              (set-cdr! result *global-stack*)
              (set-cdr! p '())
              (set! *global-stack* result))
            (loop (cdr p))))))

(define (dynamic-forth-reverse-stack)
  (set! *global-stack* (reverse *global-stack*)))

(define (dynamic-forth-depth)
  (push-global-stack *global-stack-depth*))

(define (dynamic-forth-pick) 
  (my-with-pop (pos)
    (let loop ((d pos) (p *global-stack*))
      (if (> d 0)
          (loop (- d 1) (cdr p))
          (push-global-stack (car p))))))

(define (dynamic-forth-roll)
  (my-with-pop (pos)
    (when (> pos 0)
      (let loop ((d pos) (p *global-stack*))
        (if (> d 1)
            (loop (- d 1) (cdr p))
            (begin
              (set! *global-stack* (cons (cadr p) *global-stack*))
              (set-cdr! p (cddr p))))))))

(define (_not) (push-global-stack (my-if (pop-global-stack) 0 1)))

(define (my-collect)
  (let ((d (car *collect-stack*)))
    (set! *collect-stack* (cdr *collect-stack*))
    (let loop ((lst '()) (i (- *global-stack-depth* d)))
      (if (> i 0)
       (my-with-pop (val)
          (loop (cons val lst) (- i 1)))
       lst ))))

(define (my-collect-mark) 
(set! *collect-stack* (cons *global-stack-depth* *collect-stack*))) 

(define my-list-start my-collect-mark)

(define (my-list-end) 
  (push-global-stack (my-collect)))
  
(define dynamic-forth-my-cond-start my-collect-mark)

(define (dynamic-forth-my-cond-end) 
  (let ((cond-lst (my-collect)))
    (let loop ((lst cond-lst))
      (unless (null? lst)
            ((car lst))
            (my-if (pop-global-stack)
                   ((cadr lst))
                   (loop (cddr lst)))))))
 
(define dynamic-forth-my-case-start my-collect-mark)
 
(define (dynamic-forth-my-case-end) 
   (let ((case-lst (my-collect))
         (value (pop-global-stack)))
     (let loop ((lst case-lst))
       (if (not (null? lst))
           (if (or (and (list? (car lst)) (member value (car lst)))
                   (eq? value (car lst)))
               ((cadr lst))
               (loop (cddr lst)))))))

(define (dynamic-forth-_while)
  (my-with-pop (test body)
   (let loop ()
      (test)
      (my-when (pop-global-stack)
               (body)
               (loop)))))

(define (dynamic-forth-_until)
  (my-with-pop (test body)
   (let loop ()
      (test)
      (my-unless (pop-global-stack)
               (body)
               (loop)))))

(define (dynamic-forth-do-while)
  (my-with-pop (body test)
   (let loop ()
     (body)
     (test)
     (my-if (pop-global-stack)
            (loop)))))  

(define (dynamic-forth-do-until)
  (my-with-pop (body test)
   (let loop ()
     (body)
     (test)
     (my-unless (pop-global-stack)
                (loop)))))

(define (dynamic-forth-_loop)
  (my-with-pop (start test update body)
   (start)
   (let loop () 
     (test)
     (my-when (pop-global-stack)
              (body)
              (update)
              (loop)))))

(define (dynamic-forth-repeat)
  (my-with-pop (n body)
    (let loop ((i n))
      (when (> i 0)
        (body)
        (loop (- i 1))))))

(define (dynamic-forth-each)
  (my-with-pop (lst body)
    (let loop ((p lst))
      (unless (null? p)
        (push-global-stack (car p))
        (body)
        (loop (cdr p))))))

(define (dynamic-forth-_for)
  (my-with-pop (init max body)
   (let loop ((i init))
     (when (< i max)
       (push-global-stack i)
       (body)
       (loop (+ i 1))))))

(define (dynamic-forth-_down)
  (my-with-pop (init min body)
   (let loop ((i init))
     (when (>= i min)
       (push-global-stack i)
       (body)
       (loop (- i 1))))))

(define (dynamic-forth-_for-by)
  (my-with-pop (init max step body)
   (let loop ((i init))
     (when (< i max)
       (push-global-stack i)
       (body)
       (loop (+ i step))))))

(define (dynamic-forth-_down-by)
  (my-with-pop (init min step body)
   (let loop ((i init))
     (when (>= i min)
       (push-global-stack i)
       (body)
       (loop (- i step))))))

(define (dynamic-forth-_if)
  (my-with-pop (c true-body false-body)
     (my-if c (true-body) (false-body))))

(define (dynamic-forth-_when)
  (my-with-pop (c body)
     (my-when c (body))))

(define (dynamic-forth-_unless)
  (my-with-pop (c body)
     (my-unless c (body))))

(define (_==)
  (my-with-pop (a b)
   (if (and (number? a) (number? b)) 
       (push-global-stack (if (= a b) 1 0))
       (push-global-stack (if (eq? a b) 1 0))))) 

(define (_!=) 
  (my-with-pop (a b)
   (if (and (number? a) (number? b))
       (push-global-stack (if (= a b) 0 1))
       (push-global-stack (if (eq? a b) 0 1)))))

(define (_>=) 
  (my-with-pop (a b)
   (push-global-stack (if (>= a b) 1 0))))

(define (_<=) 
  (my-with-pop (a b)
   (push-global-stack (if (<= a b) 1 0))))

(define (_<) 
  (my-with-pop (a b)
   (push-global-stack (if (< a b) 1 0))))

(define (_>) 
  (my-with-pop (a b)
   (push-global-stack (if (> a b) 1 0))))

(define (_+)
  (my-with-pop (a b)
   (push-global-stack (+ a b))))

(define (_-)
  (my-with-pop (a b)
   (push-global-stack (- a b))))

(define (_/)
  (my-with-pop (a b)
   (push-global-stack (/ a b))))

(define (_*)
  (my-with-pop (a b)
   (push-global-stack (* a b))))

(define (dynamic-forth-div)
  (my-with-pop (a b)
   (push-global-stack (quotient a b))))

(define (_%)
  (my-with-pop (a b)
   (push-global-stack (remainder a b))))

(define (_car)
  (my-with-pop (lst)
   (push-global-stack (car lst))))

(define (_cdr)
  (my-with-pop (lst)
   (push-global-stack (cdr lst))))

(define (_null?)
  (my-with-pop (lst)
   (push-global-stack (if (null? lst) 1 0))))

(define (_cons)
  (my-with-pop (lst e)
   (push-global-stack (cons e lst))))

(define (dynamic-forth-call)
  ((pop-global-stack)))

(define (dynamic-forth-_point)
  (call-with-current-continuation 
   (lambda (cc)
     (my-with-pop (fn)
      (push-global-stack cc)
      (fn)))))

(define (my-yield ret)
  (call-with-current-continuation 
    (lambda (back)
      (push-global-stack
        (lambda () 
          (call-with-current-continuation
            (lambda (dynamic-forth-return)
              (back dynamic-forth-return)))))
      (ret))))

(define (dynamic-forth-pr)
  (display (pop-global-stack)))

(define (dynamic-forth-prn)
  (display (pop-global-stack))
  (newline))

(define (dynamic-forth-nl)
  (newline))

(define (dynamic-forth-dup) 
  (push-global-stack (car *global-stack*)))

(define (dynamic-forth-swap)
  (my-with-pop (a b)
    (push-global-stack b)
    (push-global-stack a)))

(define (dynamic-forth-drop)
  (pop-global-stack))

(define (_list?)
  (my-with-pop (lst)
    (push-global-stack (if (list? lst) 1 0))))

END

# In macros variable 
# Variables start with big letters so the compiler will not
# expand them; const,lambdas,list start with small letters.

# I treat \n as a word to make it easier to read the scheme code.
define_macro("\n",[],"\n",0);

define_macro("(",[],"(my-list-start)",0);
define_macro(")",[],"(my-list-end)",0);

define_macro("setvar",["X"],"(set! X (pop->func))",0);
define_macro("setfun",["X"],"(set! X ($pop))",0);

define_macro("+",[],"(_+)",0);
define_macro("-",[],"(_-)",0);
define_macro("*",[],"(_*)",0);
define_macro("/",[],"(_/)",0);
define_macro("%",[],"(_%)",0);
define_macro("==",[],"(_==)",0);
define_macro("!=",[],"(_!=)",0);
define_macro(">=",[],"(_>=)",0);
define_macro("<=",[],"(_<=)",0);
define_macro(">",[],"(_>)",0);
define_macro("<",[],"(_<)",0);

define_macro("car",[],"(_car)",0);
define_macro("cdr",[],"(_cdr)",0);
define_macro("null?",[],"(_null?)",0);
define_macro("cons",[],"(_cons)",0);
define_macro("list?",[],"(_list?)",0);
define_macro("not",[],"(_not)",0);

define_macro(";",[],"] swap call",1);
define_macro("defvar*",["X","v"],"v defvar X",1);
define_macro("setvar*",["X","v"],"v setvar X",1);
define_macro("defun*",["X","l"],"l defun X",1);
define_macro("setfun*",["X","l"],"l setfun X",1);

define_macro("defun+",["X","l"]
  ,"[ defun return l call return ] my-fun->fun+ defun X",1);
define_macro("setfun+",["X","l"]
  ,"[ defun return l call return ] my-fun->fun+ setfun X",1);

define_macro("yield",[],"(set! dynamic-forth-return (my-yield dynamic-forth-return))",0);

define_macro("cond",[],"[ call my-cond-end ] [ my-cond-start",1); 
define_macro("case",[],"[ call my-case-end ] [ my-case-start",1);

define_macro("if",["t","f"],"t f _if",1);
define_macro("when",["b"],"b _when",1);
define_macro("unless",["b"],"b _unless",1);

define_macro("point",["X"],"[ _point ] [ defun X",1);

define_macro("while",["c","b"],"c b _while",1);
define_macro("until",["c","b"],"c b _until",1);
define_macro("for",["s","e","b"],"s e b _for",1);
define_macro("down",["s","e","b"],"s e b _down",1);
define_macro("for-by",["s","e","u","b"],"s e u b _for-by",1);
define_macro("down-by",["s","e","u","b"],"s e u b _down-by",1);
define_macro("loop",["i","c","u","b"],"i c u b _loop",1);

print $scheme_code;
print compile($text);
