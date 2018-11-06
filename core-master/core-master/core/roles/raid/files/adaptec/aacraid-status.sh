#!/usr/bin/python

import os
import re
import sys
import datetime
import time
now = datetime.date.today()

if len(sys.argv) > 2:
    print 'Usage: aacraid-status [-d]'
    sys.exit(1)

printarray = True
printcontroller = True

bad = False

if len(sys.argv) > 1:
    if sys.argv[1] == '-d':
        printarray = False
        printcontroller = False
    else:
        print 'Usage: aacraid-status [-d]'
        sys.exit(1)

# Get command output
def getOutput(cmd):
    output = os.popen(cmd+' 2>/dev/null')
    lines = []
    for line in output:
        if not re.match(r'^$',line.strip()):
            lines.append(line.strip())
    return lines

def returnControllerNumber(output):
    for line in output:
        if re.match(r'^Controllers found: [0-9]+$',line.strip()):
            return int(line.split(':')[1].strip().strip('.'))

def returnControllerModel(output):
    for line in output:
        if re.match(r'^Controller Model.*$',line.strip()):
            return line.split(':')[1].strip()

def returnControllerStatus(output):
    for line in output:
        if re.match(r'^Controller Status.*$',line.strip()):
            return line.split(':')[1].strip()

def returnArrayIds(output):
    ids = []
    for line in output:
        if re.match(r'^Logical device number [0-9]+$',line.strip()):
            ids.append(line.strip('Logical device number').strip())
    return ids

def returnArrayInfo(output):
    members = []
    for line in output:
        # RAID level may be either N or Simple_Volume
        # (a disk connected to the card, not hotspare, not part of any array)
        if re.match(r'^RAID level\s+: .+$',line.strip()):
            type = line.split(':')[1].strip()
        if re.match(r'^Status of logical device\s+: .*$',line.strip()):
            status = line.split(':')[1].strip()
        if re.match(r'^Size\s+: [0-9]+ MB$',line.strip()):
            size = str(int(line.strip('MB').split(':')[1].strip()) / 1000)
        if re.match(r'.*Segment [0-9]+\s+: .*$',line.strip()):
            splitter = re.compile('(\(.*\))')
            line = line.split(' : ')[1]
            if re.match(r'Present.*$',splitter.split(line)[0]):
                linedisk=splitter.split(line)[1]
                if re.match(r'\(Controller.*$',linedisk):
                    members.append(linedisk.split(':')[2].split(',')[0]+','+linedisk.split(':')[3].strip(')'))
                else:
                    members.append(linedisk.strip('(').strip(')'))
            else:
                members.append('-1,-1')
    return [type,status,size,members]

def returnControllerTasks(output):
    arrayid = False
    type = False
    state = False
    tasks = []
    for line in output:
        if re.match(r'^Logical device\s+: [0-9]+$',line.strip()):
            arrayid = line.split(':')[1].strip()
        if re.match(r'^Current operation\s+: .*$',line.strip()):
            type = line.split(':')[1].strip()
        if re.match(r'^Percentage complete\s+: [0-9]+$',line.strip()):
            state = line.split(':')[1].strip()
        if arrayid != False and type != False and state != False:
            tasks.append([arrayid,type,state])
            arrayid = False
            type = False
            state = False
    return tasks

def returnDisksInfo(output):
    diskid = False
    vendor = False
    model = False
    state = False
    disks = []
    for line in output:
        if re.match(r'^Reported Channel,Device(\(T:L\))?\s+: [0-9]+,[0-9]+(\([0-9]+:[0-9]+\))?$',line.strip()):
            diskid = re.split('\s:\s',line)[1].strip()
            diskid = re.sub('\(.*\)','',diskid)
        if re.match(r'^State\s+: .*$',line.strip()):
            state = line.split(':')[1].strip()
        if re.match(r'^Vendor\s+: .*$',line.strip()):
            vendor = line.split(':')[1].strip()
        if re.match(r'^Model\s+: .*$',line.strip()):
            model = line.split(':')[1].strip()
        if diskid != False and model != False and state != False:
            disks.append([diskid,state,vendor,model])
            diskid = False
            vendor = False
            model = False
            state = False
    return disks

def returnDeadDisk(output):
    serial = False
    year = False
    mon = False
    day = False
    disks = []
    for line in output:
        if re.match(r'^serialNumber \.+ .*$',line.strip()):
            serial = re.split('\.+',line)[1].strip()
        if re.match(r'^rtcYear \.+ .*$',line.strip()):
            year = re.split('\.+',line)[1].strip()
        if re.match(r'^rtcMonth \.+ .*$',line.strip()):
            mon = re.split('\.+',line)[1].strip()
        if re.match(r'^rtcDay \.+ .*$',line.strip()):
            day = re.split('\.+',line)[1].strip()
        if serial != False and year != False and mon != False and day != False:
            if (year == str(now.year) and mon == str(now.month) and day == str(now.day)):
                disks.append([serial,year,mon,day])
            serial = False
            year = False
            mon = False
            day = False

    return disks

cmd = 'arcconf GETVERSION'
output = getOutput(cmd)
controllernumber = returnControllerNumber(output)

# List controllers
if printcontroller:
    print '-- Controller informations --'
    print '-- ID | Model | Status'
    controllerid = 1
    while controllerid <= controllernumber:
        cmd = 'arcconf GETCONFIG '+str(controllerid)
        output = getOutput(cmd)
        controllermodel = returnControllerModel(output)
        controllerstatus = returnControllerStatus(output)
        if controllerstatus != 'Optimal':
            bad = True
        print 'c'+str(controllerid-1)+' | '+controllermodel+' | '+controllerstatus
        controllerid += 1
    print ''

# List arrays
if printarray:
    controllerid = 1
    print '-- Arrays informations --'
    print '-- ID | Type | Size | Status | Task | Progress'
    while controllerid <= controllernumber:
        arrayid = 0
        cmd = 'arcconf GETCONFIG '+str(controllerid)
        output = getOutput(cmd)
        arrayids = returnArrayIds(output)
        for arrayid in arrayids:
            cmd = 'arcconf GETCONFIG '+str(controllerid)+' LD '+str(arrayid)
            output = getOutput(cmd)
            arrayinfo = returnArrayInfo(output)
            if arrayinfo[1] != 'Optimal':
                bad = True
            cmd = 'arcconf GETSTATUS '+str(controllerid)
            output = getOutput(cmd)
            tasksinfo = returnControllerTasks(output)
            done = False
            # Print RAIDX if a level of RAID is returned
            # Else print the variable content (ie: Simple_Volume)
            try:
                int(arrayinfo[0])
                raidtype = 'RAID'+arrayinfo[0]
            except:
                raidtype = arrayinfo[0]
            for tasks in tasksinfo:
                if int(tasks[0]) == int(arrayid):
                    print 'c'+str(controllerid-1)+'u'+str(arrayid)+' | '+raidtype+' | '+arrayinfo[2]+'G | '+arrayinfo[1]+' | '+tasks[1]+' | '+tasks[2]+'%'
                    done = True
                    break
            if done == False:
                print 'c'+str(controllerid-1)+'u'+str(arrayid)+' | '+raidtype+' | '+arrayinfo[2]+'G | '+arrayinfo[1]
        controllerid += 1
    print ''


# List disks
controllerid = 1
print '-- Disks informations'
print '-- ID | Model | Status'
while controllerid <= controllernumber:
    arrayid = 0
    cmd = 'arcconf GETCONFIG '+str(controllerid)
    output = getOutput(cmd)
    arrayids = returnArrayIds(output)
    for arrayid in arrayids:
        cmd = 'arcconf GETCONFIG '+str(controllerid)+' LD '+str(arrayid)
        output = getOutput(cmd)
        arrayinfo = returnArrayInfo(output)
        cmd = 'arcconf GETCONFIG '+str(controllerid)+' PD'
        output = getOutput(cmd)
        diskinfo = returnDisksInfo(output)
        for member in arrayinfo[3]:
            i = 0
            for disk in diskinfo:
                if not ((disk[1] == 'Online') or (disk[1] == 'Ready')):
                    bad = True
                if disk[0] == member:
                    print 'c'+str(controllerid-1)+'u'+str(arrayid)+'d'+str(i)+' | '+disk[3]+' '+' | '+disk[1]
                i += 1
    cmd = 'arcconf GETLOGS '+str(controllerid)+' DEAD tabular'
    output = getOutput(cmd)
    deaddisk = returnDeadDisk(output)
    for disk in deaddisk:
        print 'Disk in the DEAD log - Alert on disk with serial: '+disk[0]
        bad = True
    controllerid += 1

if bad:
    print '\nThere is at least one disk/array in a NOT OPTIMAL state.'
    sys.exit(1)

