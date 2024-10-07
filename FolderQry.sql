select f.name as fname, ff.name, ffu.ops from arsfol f
    inner join arsfolfld ff
        on f.fid = ff.fid
        and ff.name='LDD' 
    inner join arsfolfldusr ffu
        on f.fid=ffu.fid
            and bitand(ffu.ops,256)=0
        and ff.field = ffu.field;
