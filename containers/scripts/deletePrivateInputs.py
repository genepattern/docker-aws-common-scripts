import sys
import os
import subprocess

filename = sys.argv[1]
username = sys.argv[2]
local_root = sys.argv[3]

print("Scanning " + filename+ " for inputs to delete from compute node for user "+ username + " and local root -" + local_root+ "-")
file1 = open(filename, 'r')
allLines = file1.readlines()
for aline in allLines:
    line = aline.strip()
    if (line.startswith("\""+local_root)):
        if (line.find(username) > 0) :
            endQuotePos = line.rindex("\"")
            dirName = line[:endQuotePos+1]
            try:
                print("        deleting "+ dirName + " from compute node")
                subprocess.call("rm -r " + dirName, shell=True, env=os.environ)
            except Exception as ex:
                print("        -- ERROR - could not delete " + dirName)
                print(type(ex))
                print(ex)

print("Done")

