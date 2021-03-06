/*
 * opencog/attention/RentCollectionAgent.cc
 *
 * Written by Roman Treutlein
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
#include <math.h>
#include <time.h>

#include <opencog/util/Config.h>
#include <opencog/util/mt19937ar.h>
#include <opencog/attention/atom_types.h>

#define DEPRECATED_ATOMSPACE_CALLS
#include <opencog/atomspace/AtomSpace.h>

#include "WARentCollectionAgent.h"

//#define DEBUG

using namespace opencog;

WARentCollectionAgent::WARentCollectionAgent(CogServer& cs) : RentCollectionBaseAgent(cs)
{
    // READ SLEEPING TIME HERE
    set_sleep_time(2000);
    SAMPLE_SIZE = 5;
}

void WARentCollectionAgent::selectTargets(HandleSeq &targetSetOut)
{
    HandleSeq atoms;

    _as->get_all_atoms(atoms);

    if (atoms.size() == 0) return;

    std::default_random_engine generator;
    std::uniform_int_distribution<int> distribution(0, atoms.size() - 1);

    for (unsigned int i = 0; (i < SAMPLE_SIZE and i < atoms.size()); i++) {
        HandleSeq tmp;

        // Randomly sample 50% of the atoms in the atomspace.
        for (unsigned int i = 0; i < atoms.size() / 2; i++) {
            int idx = distribution(generator);
            tmp.push_back(atoms[idx]);
        }

        auto result = std::max_element(tmp.begin(), tmp.end(), []
                                       (const Handle& h1, const Handle & h2)
        {
            return (h1->getSTI() > h2->getSTI());
        });

        // Select the atoms with the highest STI amongst the samples
        targetSetOut.push_back(*result);

        // set diffusionSource vector to the current samples.
        atoms = tmp;
    }
}
