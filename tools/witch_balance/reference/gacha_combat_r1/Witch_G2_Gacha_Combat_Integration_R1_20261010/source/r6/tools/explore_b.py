from explore_support import sweep,POLICIES
from support_ai_b import CANDIDATES
import sys
POLICIES.update(CANDIDATES)
sweep(sys.argv[1],start=300001,n=100)
