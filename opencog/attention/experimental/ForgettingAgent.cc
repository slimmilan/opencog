/*
 * opencog/attention/ForgettingAgent.cc
 *
 * Copyright (C) 2008 by OpenCog Foundation
 * Written by Joel Pitt <joel@fruitionnz.com>
 * All Rights Reserved
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License v3 as
 * published by the Free Software Foundation and including the exceptions
 * at http://opencog.org/wiki/Licenses
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program; if not, write to:
 * Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <algorithm>
#include <sstream>

#define DEPRECATED_ATOMSPACE_CALLS
#include <opencog/atomspace/AtomSpace.h>

#include <opencog/cogserver/server/Agent.h>
#include <opencog/cogserver/server/CogServer.h>
#include <opencog/cogserver/server/Factory.h>
#include <opencog/attention/atom_types.h>
#include <opencog/util/Config.h>
#include "ForgettingAgent.h"

using namespace opencog;

ForgettingAgent::ForgettingAgent(CogServer& cs) :
    Agent(cs)
{
    std::string defaultForgetThreshold;
    std::ostringstream buf;

    // No limit to lti of removed atoms
    // Convert MAXLTI to a string for storing in the configuration
    buf << AttentionValue::MAXLTI;
    defaultForgetThreshold = buf.str();
    config().set("ECAN_FORGET_THRESHOLD",defaultForgetThreshold);

    forgetThreshold = (AttentionValue::lti_t)
                      (config().get_int("ECAN_FORGET_THRESHOLD"));

    //Todo: Make configurable
    maxSize = config().get_int("ECAN_ATOMSPACE_MAXSIZE");
    accDivSize = config().get_int("ECAN_ATOMSPACE_ACCEPTABLE_SIZE_SPREAD");

    // Provide a logger, but disable it initially
    log = NULL;
    setLogger(new opencog::Logger("ForgettingAgent.log", Logger::WARN, true));
}

void ForgettingAgent::run()
{
    log->fine("=========== ForgettingAgent::run =======");
    forget();
}

void ForgettingAgent::forget()
{
    HandleSeq atomsVector;
    std::back_insert_iterator<HandleSeq> output2(atomsVector);
    int count = 0;
    int removalAmount;
    bool recursive;

    _as->get_handles_by_type(output2, ATOM, true);

    int asize = atomsVector.size();
    if (asize < (maxSize + accDivSize)) {
        return;
    }

    fprintf(stdout,"Forgetting Stuff, Atomspace Size: %d \n",asize);
    // Sort atoms by lti, remove the lowest unless vlti is NONDISPOSABLE
    std::sort(atomsVector.begin(), atomsVector.end(), ForgettingLTIThenTVAscendingSort(_as));

    removalAmount = asize - (maxSize - accDivSize);
    log->info("ForgettingAgent::forget - will attempt to remove %d atoms", removalAmount);

    for (unsigned int i = 0; i < atomsVector.size(); i++)
    {
        if (atomsVector[i]->getAttentionValue()->getLTI() <= forgetThreshold
                && count < removalAmount)
        {
            if (atomsVector[i]->getAttentionValue()->getVLTI() == AttentionValue::DISPOSABLE )
            {
                std::string atomName = _as->atom_as_string(atomsVector[i]);
                log->fine("Removing atom %s", atomName.c_str());
                // TODO: do recursive remove if neighbours are not very important
                IncomingSet iset = atomsVector[i]->getIncomingSet(_as);
                recursive = true;
                for (LinkPtr h : iset)
                {
                    if (h->getType() != ASYMMETRIC_HEBBIAN_LINK) {
                        recursive = false;
                        break;
                    }
                }
                if (!recursive)
                    continue;

                atomsVector[i]->setSTI(0);
                atomsVector[i]->setLTI(0);
                if (!_as->remove_atom(atomsVector[i],recursive)) {
                    // Atom must have already been removed through having
                    // previously removed atoms in it's outgoing set.
                    log->error("Couldn't remove atom %s", atomName.c_str());
                }
                count++;
                count += iset.size();
            }
        } else {
            break;
        }
    }
    log->info("ForgettingAgent::forget - %d atoms removed.", count);

}
