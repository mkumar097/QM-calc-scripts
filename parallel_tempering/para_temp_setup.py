#! /usr/bin/env python3.4

########################################################################
#                                                                      #
# This script was written by Thomas Heavey in 2015.                    #
#        theavey@bu.edu     thomasjheavey@gmail.com                    #
#                                                                      #
# Copyright 2015 Thomas J. Heavey IV                                   #
#                                                                      #
# Licensed under the Apache License, Version 2.0 (the "License");      #
# you may not use this file except in compliance with the License.     #
# You may obtain a copy of the License at                              #
#                                                                      #
#    http://www.apache.org/licenses/LICENSE-2.0                        #
#                                                                      #
# Unless required by applicable law or agreed to in writing, software  #
# distributed under the License is distributed on an "AS IS" BASIS,    #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or      #
# implied.                                                             #
# See the License for the specific language governing permissions and  #
# limitations under the License.                                       #
#                                                                      #
########################################################################

# This is written to work with python 3.4 because it should be good to
# be working on the newest version of python.

import glob
import argparse
import math
import subprocess
import readline
import os
import shutil
from datetime import datetime

__version__ = '0.1.1'

parser = argparse.ArgumentParser(description='A script to help setup parallel'
                                             'tempering jobs in GROMACS with'
                                             'PLUMED')
parser.add_argument('-l', '--template', default='templatemdp.txt',
                    help='name of template file')
parser.add_argument('-s', '--start_temp', default=205,
                    help='starting (lowest) temperature')
parser.add_argument('-n', '--number', default=16,
                    help='number of replicates')
parser.add_argument('-e', '--scaling_exponent', default=0.025,
                    help='exponent by which to scale temps')
parser.add_argument('-b', '--base_name', default='npt',
                    help='base name for output mdp and tpr files')
parser.add_argument('-p', '--topology',
                    default='../taddol_3htmf_stilbene_em.top',
                    help='name of topology file (.top)')
parser.add_argument('-c', '--structure', default='../major_endo.gro',
                    help='structure file (.gro) ')
parser.add_argument('--index', default='../index.ndx',
                    help='index files')
parser.add_argument('--version', action='version',
                    version='%(prog)s v{}'.format(__version__))
args = parser.parse_args()


for i in range(args.number):
    mdp_name = args.base_name + str(i) + '.mdp'
    temp = args.start_temp * math.exp(i * args.scaling_exponent)
    with open(args.template, 'r') as template, \
            open(mdp_name, 'w') as out_file:
        for line in template:
            if 'TempGoesHere' in line:
                line = line.replace('TempGoesHere', str(temp))
            out_file.write(line)
    command_line = ['grompp_mpi',
                    '-f', mdp_name,
                    '-p', args.topology,
                    '-c', args.structure,
                    '-n', args.index,
                    '-o', mdp_name.replace('mdp', 'tpr'),
                    '-maxwarn', '2']
    # command_line = 'grompp_mpi -f {} '.format(mdp_name) + \
    #                '-p ../taddol_3htmf_stilbene_em.top -c ' \
    #                '../major_endo.gro -n ../index.ndx -o ' \
    #                '{} -maxwarn 2'.format(mdp_name.replace('mdp', 'tpr'))
    with open('gromacs_compile_output.log', 'w') as log_file:
        with subprocess.Popen(command_line,
                              stdout=subprocess.PIPE, bufsize=1,
                              universal_newlines=True) as proc:
            for line in proc.stdout:
                log_file.write(line)



