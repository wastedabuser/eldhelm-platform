cd $1
echo perl check.pl $2 -dump -syntax -static -unittest -doc
perl check.pl $2 -dump -syntax -static -unittest -doc