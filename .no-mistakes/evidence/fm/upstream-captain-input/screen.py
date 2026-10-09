import re,sys
d=open(sys.argv[1],'rb').read().decode('utf-8','replace')
d=d[-int(sys.argv[2]) if len(sys.argv)>2 else -6000:]
d=re.sub(r'\x1b\[(\d+)C',lambda m:' '*int(m.group(1)),d)
d=re.sub(r'\x1b\[\d+;\d+H','\n',d)
d=re.sub(r'\x1b\][^\x07\x1b]*(\x07|\x1b\\)','',d)
d=re.sub(r'\x1b\[[0-9;?<>=]*[A-Za-z]','',d)
d=d.replace('\r','\n')
print(re.sub(r'\n\s*\n+','\n',d))
