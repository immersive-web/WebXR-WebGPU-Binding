.PHONY: all index.html

all: index.html

index.html: index.bs
	curl https://api.csswg.org/bikeshed/ -F file=@index.bs -F output=err
	curl https://api.csswg.org/bikeshed/ -F file=@index.bs -F force=1 > index.html | tee

local: index.bs
	bikeshed --die-on=everything spec index.bs
