cd $1
echo perl check.pl $2 -dump -syntax -static -unittest
perl check.pl $2 -dump -syntax -static -unittest