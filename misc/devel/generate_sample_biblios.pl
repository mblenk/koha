#!/usr/bin/perl

# Copyright 2026 Openfifth
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

generate_sample_biblios.pl - Populate Koha with 1000 diverse sample biblio records

=head1 SYNOPSIS

    perl misc/devel/generate_sample_biblios.pl --confirm

=head1 DESCRIPTION

Deletes all existing biblio and authority records, then inserts 1000 new biblio records
spanning 40 subject areas across 8 knowledge domains. Records are distributed across
five MARC field profiles to give varied coverage of the default marc_fields_config
fields (title, subtitle, author, 6xx subject headings, 520 summary).

Authority records are created for all subject headings (TOPIC_TERM, GEOGR_NAME,
PERSO_NAME) and linked to biblio records via $9 subfields in 650/651/600 fields.
Selected topics include variant forms (450/451/400 fields) to enrich semantic search
vectors with USE-FOR authority data.

After inserting records the script rebuilds the standard Elasticsearch search index for
both biblios and authorities. Vector embeddings are NOT generated — trigger those from
the embedding providers UI.

=head1 OPTIONS

=over

=item B<--confirm>

Required. Confirms that all existing biblio records should be deleted.

=item B<--help>

Display this help.

=back

=cut

use Modern::Perl;

use Getopt::Long qw( GetOptions );
use Pod::Usage   qw( pod2usage );

use Koha::Script;
use C4::Biblio          qw( AddBiblio DelBiblio );
use C4::AuthoritiesMarc qw( AddAuthority );
use C4::Context;
use MARC::Record;
use MARC::Field;
use Koha::Authorities;
use Koha::Biblios;

my ( $confirm, $help );
GetOptions(
    'confirm' => \$confirm,
    'help'    => \$help,
);

pod2usage( -verbose => 2 ) if $help;

unless ($confirm) {
    pod2usage(
        -message => "ERROR: --confirm is required.\n" . "WARNING: this script deletes ALL existing biblio records.\n",
        -verbose => 1,
    );
}

# ---------------------------------------------------------------------------
# TOPIC DATA
# 40 sub-topics × 25 records (5 profiles × 5) = 1000 records total.
# ---------------------------------------------------------------------------

my @TOPICS = (

    # === NATURAL SCIENCES ===

    {
        name   => 'Quantum Physics',
        titles => [
            'Quantum Mechanics',
            'The Quantum World',
            'Wave Functions and Probability',
            'Quantum Entanglement',
            'Principles of Quantum Theory',
        ],
        subtitles => [
            'An Introduction to Modern Theory',
            'From Photons to Quarks',
            'Mathematical Foundations',
            'Theory and Experiment',
            'A Graduate Course',
        ],
        authors => [
            'Harrington, James R.',
            'Patel, Sunita',
            'Müller, Klaus',
            'Chen, Wei',
            'Okonkwo, Adaeze N.',
        ],
        subjects => [
            'Quantum mechanics',
            'Wave-particle duality',
            'Quantum entanglement',
            'Uncertainty principle',
            'Quantum field theory',
            'Schrödinger equation',
        ],
        geo_subjects      => [ 'Switzerland', 'United States', 'Europe' ],
        personal_subjects => [
            'Heisenberg, Werner, 1901-1976',
            'Schrödinger, Erwin, 1887-1961',
            'Bohr, Niels, 1885-1962',
        ],
        corp_subjects => [
            'European Organization for Nuclear Research',
            'American Physical Society',
            'Max Planck Institute for Physics',
        ],
        form_genres   => [ 'Textbooks', 'Handbooks, manuals, etc.', 'Conference proceedings' ],
        variant_forms => {
            'Quantum mechanics'    => [ 'Quantum physics', 'Wave mechanics', 'Quantum theory' ],
            'Quantum entanglement' => [ 'Quantum nonlocality', 'Entanglement (Physics)', 'Quantum correlation' ],
        },
        summaries   => [
            'An authoritative introduction to quantum mechanics covering wave functions, measurement theory, and the uncertainty principle. Bridges classical and quantum descriptions of physical systems with extensive worked examples.',
            'A concise overview of quantum entanglement and its implications for quantum information and cryptography.',
            'A graduate-level text covering the mathematical structure of quantum theory including Hilbert spaces, linear operators, and eigenvalue problems, with applications to atomic and molecular systems.',
            'Explores the experimental basis of quantum mechanics through landmark experiments from the photoelectric effect to Bell inequality tests.',
            'A rigorous introduction to quantum field theory covering canonical quantisation, path integrals, and Feynman diagrams.',
        ],
    },

    {
        name   => 'Classical and Thermal Physics',
        titles => [
            'Thermodynamics and Statistical Mechanics',
            'Classical Mechanics',
            'Fluid Dynamics',
            'Heat and Mass Transfer',
            'Statistical Physics',
        ],
        subtitles => [
            'Principles and Applications',
            'An Analytical Approach',
            'Fundamentals and Applications',
            'Theory and Practice',
            'From Boltzmann to Black Holes',
        ],
        authors => [
            'Anderson, Peter T.',
            'Yoshida, Kenji',
            'Mensah, Kwame',
            'Rivera, Elena',
            'Singh, Arun Kumar',
        ],
        subjects => [
            'Thermodynamics',
            'Statistical mechanics',
            'Classical mechanics',
            'Fluid dynamics',
            'Heat transfer',
            'Entropy',
        ],
        geo_subjects      => [ 'Germany', 'United States', 'Great Britain' ],
        personal_subjects => [
            'Boltzmann, Ludwig, 1844-1906',
            'Maxwell, James Clerk, 1831-1879',
            'Carnot, Sadi, 1796-1832',
        ],
        corp_subjects => [
            'Royal Society (Great Britain)',
            'American Institute of Physics',
            'Deutsche Physikalische Gesellschaft',
        ],
        form_genres => [ 'Textbooks', 'Problem sets', 'Handbooks, manuals, etc.' ],
        summaries   => [
            'A comprehensive treatment of thermodynamics and statistical mechanics covering the laws of thermodynamics, entropy, and statistical distributions from Maxwell-Boltzmann to quantum statistics.',
            'Presents classical mechanics through Lagrangian and Hamiltonian formalisms with applications to rigid body motion, oscillations, and celestial mechanics.',
            'Introduces fluid dynamics including the Navier-Stokes equations, turbulence, and applications to aerodynamics and oceanography.',
            'A focused study of heat and mass transfer with engineering applications in thermal system design.',
            'An advanced treatment of statistical physics exploring the connection between microscopic dynamics and macroscopic thermodynamic behaviour.',
        ],
    },

    {
        name   => 'Chemistry',
        titles => [
            'Organic Chemistry',
            'Physical Chemistry',
            'Principles of Inorganic Chemistry',
            'Analytical Chemistry',
            'Chemical Kinetics and Reaction Mechanisms',
        ],
        subtitles => [
            'Structure, Reactivity, and Synthesis',
            'Thermodynamics and Kinetics',
            'Coordination Compounds and Bonding',
            'Methods and Applications',
            'From Theory to Laboratory',
        ],
        authors => [
            'Kowalski, Marta',
            'Ibrahim, Fatima',
            'Nakamura, Hiroshi',
            'Thompson, Sarah J.',
            'Adesanya, Oluwaseun',
        ],
        subjects => [
            'Organic chemistry',
            'Physical chemistry',
            'Inorganic chemistry',
            'Chemical reactions',
            'Spectroscopy',
            'Molecular structure',
        ],
        geo_subjects      => [ 'Germany', 'United States', 'Japan' ],
        personal_subjects => [
            'Mendeleev, Dmitrii Ivanovich, 1834-1907',
            'Pauling, Linus, 1901-1994',
            'Woodward, R. B. (Robert Burns), 1917-1979',
        ],
        corp_subjects => [
            'Royal Society of Chemistry',
            'American Chemical Society',
            'International Union of Pure and Applied Chemistry',
        ],
        form_genres   => [ 'Textbooks', 'Laboratory manuals', 'Handbooks, manuals, etc.' ],
        variant_forms => {
            'Organic chemistry'  => [ 'Carbon chemistry', 'Hydrocarbon chemistry', 'Carbon compounds' ],
            'Chemical reactions' => [ 'Chemical transformations', 'Chemical processes', 'Reactivity' ],
        },
        summaries   => [
            'A thorough introduction to organic chemistry covering functional groups, reaction mechanisms, stereochemistry, and spectroscopic methods for structure determination.',
            'Covers the thermodynamic and kinetic principles underlying chemical transformations, including quantum mechanics of chemical bonding and statistical thermodynamics.',
            'An authoritative treatment of inorganic chemistry including coordination chemistry, organometallic compounds, and solid-state structures.',
            'Introduces modern analytical techniques including chromatography, mass spectrometry, and electrochemical methods for chemical analysis.',
            'A detailed exploration of chemical kinetics covering rate laws, transition state theory, and catalysis mechanisms.',
        ],
    },

    {
        name   => 'Biochemistry and Molecular Biology',
        titles => [
            'Biochemistry',
            'Molecular Biology of the Cell',
            'Protein Structure and Function',
            'Enzyme Kinetics and Mechanism',
            'Molecular Genetics',
        ],
        subtitles => [
            'The Chemical Basis of Life',
            'From Genes to Proteins',
            'A Structural Approach',
            'Catalysis and Regulation',
            'Mechanisms and Applications',
        ],
        authors => [
            'Park, Ji-Young',
            'Nwosu, Chinyere',
            'Bergström, Lars E.',
            'Fernandez, Miguel A.',
            'Kapoor, Priya',
        ],
        subjects => [
            'Biochemistry',
            'Molecular biology',
            'Proteins',
            'Enzymes',
            'Nucleic acids',
            'Metabolism',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Germany' ],
        personal_subjects => [
            'Watson, James D., 1928-',
            'Crick, Francis, 1916-2004',
            'Kornberg, Arthur, 1918-2007',
        ],
        corp_subjects => [
            'Cold Spring Harbor Laboratory',
            'Medical Research Council (Great Britain)',
            'National Institutes of Health (U.S.)',
        ],
        form_genres => [ 'Textbooks', 'Handbooks, manuals, etc.', 'Review literature' ],
        summaries   => [
            'A comprehensive biochemistry textbook covering carbohydrate, lipid, protein, and nucleic acid metabolism, enzyme kinetics, signal transduction, and the molecular basis of genetic information.',
            'Examines the molecular biology of the cell from membrane structure to cell division, emphasising gene expression, protein trafficking, and cell signalling networks.',
            'Focuses on the structure, folding, and function of proteins, covering X-ray crystallography, NMR spectroscopy, and computational methods for structural analysis.',
            'A rigorous treatment of enzyme kinetics, inhibition mechanisms, and allosteric regulation, with applications in drug design and metabolic engineering.',
            'Explores the molecular mechanisms of DNA replication, transcription, translation, and gene regulation in prokaryotes and eukaryotes.',
        ],
    },

    {
        name   => 'Ecology and Evolution',
        titles => [
            'Ecology: Concepts and Applications',
            'The Theory of Evolution',
            'Population Ecology',
            'Conservation Biology',
            'Evolutionary Ecology',
        ],
        subtitles => [
            'From Individuals to Ecosystems',
            'Darwin and Beyond',
            'Dynamics and Modelling',
            'Principles and Practice',
            'Adaptation and Natural Selection',
        ],
        authors => [
            'Osei, Emmanuel',
            'Lindqvist, Anna',
            'MacAllister, Colin R.',
            'Adichie, Olumide',
            'Hernandez, Carmen R.',
        ],
        subjects => [
            'Ecology',
            'Evolution (Biology)',
            'Natural selection',
            'Population dynamics',
            'Biodiversity',
            'Ecosystem services',
        ],
        geo_subjects      => [ 'Amazon River Region', 'Africa', 'Galápagos Islands (Ecuador)' ],
        personal_subjects => [
            'Darwin, Charles, 1809-1882',
            'Wallace, Alfred Russel, 1823-1913',
            'Wilson, E. O. (Edward Osborne), 1929-2021',
        ],
        corp_subjects => [
            'World Wildlife Fund',
            'International Union for Conservation of Nature',
            'Smithsonian Institution',
        ],
        form_genres   => [ 'Textbooks', 'Field guides', 'Case studies' ],
        variant_forms => {
            'Evolution (Biology)' => [ 'Biological evolution', 'Darwinian evolution', 'Natural evolution' ],
            'Biodiversity'        => [ 'Biological diversity', 'Species diversity', 'Ecological diversity' ],
            'Natural selection'   => [ 'Survival of the fittest', 'Selective adaptation', 'Darwinism' ],
        },
        summaries   => [
            'A broad introduction to ecology covering population, community, and ecosystem ecology, with chapters on energy flow, nutrient cycling, and the effects of climate change on biodiversity.',
            'A thorough treatment of evolutionary theory from natural selection and genetic drift to speciation, co-evolution, and the evolution of social behaviour.',
            'Explores the mathematical foundations of population ecology including life tables, Leslie matrices, and Lotka-Volterra predator-prey models.',
            'An applied approach to conservation biology covering population viability analysis, habitat fragmentation, invasive species, and conservation genetics.',
            'Integrates evolutionary and ecological thinking to explain adaptation, life history strategies, and the coevolution of interacting species.',
        ],
    },

    {
        name   => 'Genetics and Cell Biology',
        titles => [
            'Genetics: From Genes to Genomes',
            'Cell Biology',
            'Epigenetics',
            'CRISPR and Genome Editing',
            'Gene Expression and Regulation',
        ],
        subtitles => [
            'A Modern Synthesis',
            'Molecular Mechanisms',
            'Heritable Changes Beyond the Sequence',
            'Principles and Applications',
            'From Prokaryotes to Eukaryotes',
        ],
        authors => [
            'Okafor, Ngozi',
            'Svensson, Erik T.',
            'Yamamoto, Akiko',
            'Dupont, Philippe',
            'Patel, Ranjit',
        ],
        subjects => [
            'Genetics',
            'Cell biology',
            'Epigenetics',
            'Gene editing',
            'Chromosomes',
            'Cell division',
        ],
        geo_subjects      => [ 'United States', 'China', 'Germany' ],
        personal_subjects => [
            'Mendel, Gregor, 1822-1884',
            'McClintock, Barbara, 1902-1992',
            'Doudna, Jennifer A.',
        ],
        corp_subjects => [
            'Human Genome Project',
            'Salk Institute for Biological Studies',
            'Wellcome Sanger Institute',
        ],
        form_genres => [ 'Textbooks', 'Laboratory manuals', 'Conference proceedings' ],
        summaries   => [
            'A comprehensive genetics textbook from Mendelian inheritance to genomics, covering molecular mechanisms of heredity, genetic mapping, and the regulation of gene expression in development.',
            'An in-depth examination of cell biology covering organelle function, the cytoskeleton, cell signalling, and the cell cycle, with emphasis on molecular mechanisms.',
            'Explores the mechanisms and biological significance of epigenetic modifications including DNA methylation, histone modification, and non-coding RNAs.',
            'A thorough treatment of CRISPR-Cas9 and related genome editing technologies, their molecular mechanisms, and applications in research and medicine.',
            'Examines the control of gene expression at transcriptional, post-transcriptional, and translational levels in both prokaryotic and eukaryotic systems.',
        ],
    },

    {
        name   => 'Earth and Atmospheric Science',
        titles => [
            'Physical Geology',
            'Atmospheric Science',
            'Oceanography',
            'Climate Dynamics',
            'Volcanology and Tectonics',
        ],
        subtitles => [
            'Exploring Earth',
            'An Introduction',
            'A Study of the Ocean',
            'Physical Foundations',
            'Earthquakes, Volcanoes, and Plates',
        ],
        authors => [
            'Petrov, Nikolai',
            'Diallo, Mariama',
            'Johansson, Lars',
            'Kim, Soo-Young',
            'Castillo, Roberto',
        ],
        subjects => [
            'Physical geology',
            'Atmospheric science',
            'Oceanography',
            'Climate change',
            'Plate tectonics',
            'Volcanology',
        ],
        geo_subjects      => [ 'Pacific Ocean', 'Antarctica', 'Iceland' ],
        personal_subjects => [
            'Wegener, Alfred, 1880-1930',
            'Arrhenius, Svante, 1859-1927',
            'Revelle, Roger, 1909-1991',
        ],
        corp_subjects => [
            'Intergovernmental Panel on Climate Change',
            'National Oceanic and Atmospheric Administration (U.S.)',
            'British Geological Survey',
        ],
        form_genres => [ 'Textbooks', 'Atlases', 'Scientific reports' ],
        summaries   => [
            'A comprehensive introduction to physical geology covering minerals, rocks, geologic structures, plate tectonics, and surface processes, with case studies from active geological settings.',
            'Covers atmospheric composition, thermodynamics, dynamics, and the global climate system, with chapters on weather forecasting and climate modelling.',
            'An introduction to physical and chemical oceanography, marine geology, and ocean circulation, with discussion of the ocean role in climate regulation.',
            'A quantitative treatment of climate dynamics covering energy balance, atmospheric circulation, ocean-atmosphere interactions, and the drivers of past and future climate change.',
            'Explores volcanic processes, tectonic settings, and seismic activity with case studies from active volcanic regions worldwide.',
        ],
    },

    {
        name   => 'Astronomy and Cosmology',
        titles => [
            'An Introduction to Astronomy',
            'Stellar Evolution',
            'Cosmology: The Science of the Universe',
            'Black Holes and Neutron Stars',
            'Planetary Science',
        ],
        subtitles => [
            'From Earth to the Cosmos',
            'From Birth to Stellar Remnants',
            'The Big Bang and Beyond',
            'Compact Objects in the Universe',
            'Atmospheres, Surfaces, and Interiors',
        ],
        authors => [
            'Nakamura, Yuki',
            'Olawale, Adebisi',
            'Korhonen, Mia',
            'Whitfield, Thomas J.',
            'Araújo, Luisa',
        ],
        subjects => [
            'Astronomy',
            'Cosmology',
            'Stars',
            'Black holes (Astronomy)',
            'Dark matter (Astronomy)',
            'Galaxies',
        ],
        geo_subjects      => [ 'Chile', 'Hawaii', 'Outer space' ],
        personal_subjects => [
            'Hubble, Edwin, 1889-1953',
            'Hawking, Stephen, 1942-2018',
            'Sagan, Carl, 1934-1996',
        ],
        corp_subjects => [
            'European Southern Observatory',
            'NASA',
            'Atacama Large Millimeter Array',
        ],
        form_genres   => [ 'Textbooks', 'Popular works', 'Atlases' ],
        variant_forms => {
            'Black holes (Astronomy)' => [ 'Collapsed stars', 'Gravitational singularities', 'Stellar black holes' ],
            'Dark matter (Astronomy)' => [ 'Non-luminous matter', 'Hidden matter', 'Cold dark matter' ],
            'Cosmology'               => [ 'Physical cosmology', 'Big Bang theory', 'Origin of the universe' ],
        },
        summaries   => [
            'A broad introduction to astronomy covering the solar system, stellar physics, galaxies, and cosmology, written for undergraduates and informed general readers.',
            'A detailed account of stellar structure and evolution from star formation in molecular clouds through main sequence evolution to compact remnants.',
            'An authoritative treatment of modern cosmology covering the Big Bang, cosmic inflation, nucleosynthesis, and large-scale structure formation.',
            'Explores the physics of compact objects including white dwarfs, neutron stars, and black holes, covering general relativity and observational evidence.',
            'Covers the formation, geology, and atmospheres of solar system bodies, including comparative planetology and the search for habitable environments.',
        ],
    },

    # === MATHEMATICS ===

    {
        name   => 'Pure Mathematics',
        titles => [
            'Abstract Algebra',
            'Real Analysis',
            'Topology',
            'Number Theory',
            'Complex Analysis',
        ],
        subtitles => [
            'Groups, Rings, and Fields',
            'A Rigorous Introduction',
            'Point-Set and Algebraic Topology',
            'From Integers to Cryptography',
            'Functions of a Complex Variable',
        ],
        authors => [
            'Blackwell, Katherine E.',
            'Sørensen, Jens Henrik',
            'Mbeki, Thabo A.',
            'Nakashima, Keiko',
            'Volkov, Sergei',
        ],
        subjects => [
            'Algebra',
            'Mathematical analysis',
            'Topology',
            'Number theory',
            'Complex analysis',
            'Abstract algebra',
        ],
        geo_subjects      => [ 'Germany', 'France', 'Russia' ],
        personal_subjects => [
            'Gauss, Carl Friedrich, 1777-1855',
            'Riemann, Bernhard, 1826-1866',
            'Galois, Évariste, 1811-1832',
        ],
        corp_subjects => [
            'American Mathematical Society',
            'London Mathematical Society',
            'International Mathematical Union',
        ],
        form_genres => [ 'Textbooks', 'Monographs', 'Problem books' ],
        summaries   => [
            'A rigorous introduction to abstract algebra covering groups, rings, fields, and Galois theory, with applications to number theory and geometry.',
            'Develops the foundations of real analysis including sequences, series, continuity, differentiation, and the Riemann integral, emphasising rigorous proof.',
            'An accessible introduction to topology covering point-set topology, metric spaces, and an introduction to homotopy and fundamental groups.',
            'A classical introduction to number theory covering divisibility, prime numbers, congruences, and quadratic residues, with an introduction to public-key cryptography.',
            'A thorough treatment of complex analysis covering analytic functions, contour integration, residues, and conformal mappings.',
        ],
    },

    {
        name   => 'Applied Mathematics',
        titles => [
            'Differential Equations',
            'Numerical Methods',
            'Mathematical Modelling',
            'Partial Differential Equations',
            'Optimisation Theory',
        ],
        subtitles => [
            'Ordinary and Partial',
            'For Engineers and Scientists',
            'From Formulation to Simulation',
            'Analytical and Numerical Methods',
            'Linear and Nonlinear Programming',
        ],
        authors => [
            'Eriksson, Björn',
            'Oduya, Emeka',
            'Lee, Hyun-Soo',
            'Markov, Dmitri V.',
            'Santos, Ana Beatriz',
        ],
        subjects => [
            'Differential equations',
            'Numerical analysis',
            'Mathematical models',
            'Partial differential equations',
            'Mathematical optimization',
            'Chaos theory',
        ],
        geo_subjects      => [ 'United States', 'Sweden', 'Brazil' ],
        personal_subjects => [
            'Newton, Isaac, 1642-1727',
            'Euler, Leonhard, 1707-1783',
            'Lorenz, Edward N., 1917-2008',
        ],
        corp_subjects => [
            'Society for Industrial and Applied Mathematics',
            'European Mathematical Society',
            'Institute of Mathematics and its Applications',
        ],
        form_genres => [ 'Textbooks', 'Computer programs', 'Handbooks, manuals, etc.' ],
        summaries   => [
            'A comprehensive treatment of ordinary and partial differential equations covering analytic methods, qualitative analysis, and numerical techniques.',
            'Introduces numerical methods for solving mathematical problems on computers, covering interpolation, numerical integration, linear systems, and differential equations.',
            'Develops skills in formulating and analysing mathematical models for real-world phenomena, with examples from biology, physics, and social science.',
            'A rigorous treatment of partial differential equations including the heat, wave, and Laplace equations, with solutions by separation of variables and transform methods.',
            'Covers the theory and algorithms of linear and nonlinear optimisation, including the simplex method, interior-point methods, and convex analysis.',
        ],
    },

    {
        name   => 'Statistics and Probability',
        titles => [
            'Probability Theory',
            'Mathematical Statistics',
            'Bayesian Analysis',
            'Stochastic Processes',
            'Statistical Learning',
        ],
        subtitles => [
            'A Rigorous Introduction',
            'Methods and Applications',
            'A Practical Introduction',
            'Theory and Applications',
            'An Introduction to Machine Learning',
        ],
        authors => [
            'Moreau, Christine',
            'Ikeda, Masahiro',
            'Osei, Kwabena',
            'Lindström, Helena',
            'Chatterjee, Souvik',
        ],
        subjects => [
            'Probabilities',
            'Mathematical statistics',
            'Bayesian statistical decision theory',
            'Stochastic processes',
            'Statistical learning',
            'Regression analysis',
        ],
        geo_subjects      => [ 'United States', 'France', 'India' ],
        personal_subjects => [
            'Bayes, Thomas, 1702-1761',
            'Fisher, Ronald Aylmer, 1890-1962',
            'Kolmogorov, A. N. (Andrei Nikolaevich), 1903-1987',
        ],
        corp_subjects => [
            'Royal Statistical Society',
            'American Statistical Association',
            'Bernoulli Society',
        ],
        form_genres => [ 'Textbooks', 'Monographs', 'Case studies' ],
        summaries   => [
            'A rigorous development of probability theory using measure theory, covering probability spaces, random variables, distributions, and limit laws.',
            'Introduces the fundamental concepts of mathematical statistics including estimation, hypothesis testing, regression, and analysis of variance.',
            'A practical introduction to Bayesian statistical inference covering prior and posterior distributions, MCMC methods, and hierarchical models.',
            'Covers the theory of stochastic processes including Markov chains, Brownian motion, Poisson processes, and their applications in finance and biology.',
            'An introduction to statistical machine learning including regression, classification, model selection, and resampling methods.',
        ],
    },

    # === COMPUTING & ENGINEERING ===

    {
        name   => 'Algorithms and Theory',
        titles => [
            'Introduction to Algorithms',
            'Computational Complexity',
            'Cryptography',
            'Graph Theory and Algorithms',
            'Automata and Computability',
        ],
        subtitles => [
            'Design, Analysis, and Implementation',
            'A Modern Introduction',
            'Theory and Practice',
            'Combinatorial Optimisation',
            'Formal Languages and Turing Machines',
        ],
        authors => [
            'Okwu, Ifeanyi',
            'Andersen, Mette L.',
            'Tanakas, Yiannis',
            'Petersen, Karl',
            'Nair, Deepa',
        ],
        subjects => [
            'Computer algorithms',
            'Computational complexity',
            'Cryptography',
            'Graph theory',
            'Formal languages',
            'Data structures (Computer science)',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Israel' ],
        personal_subjects => [
            'Turing, Alan Mathison, 1912-1954',
            'Knuth, Donald Ervin, 1938-',
            'Dijkstra, E. W. (Edsger Wybe), 1930-2002',
        ],
        corp_subjects => [
            'Association for Computing Machinery',
            'IEEE Computer Society',
            'National Security Agency (U.S.)',
        ],
        form_genres => [ 'Textbooks', 'Conference proceedings', 'Handbooks, manuals, etc.' ],
        summaries   => [
            'A comprehensive introduction to algorithms and data structures covering sorting, searching, graph algorithms, and dynamic programming, with analysis of time and space complexity.',
            'An advanced treatment of computational complexity theory, covering complexity classes, NP-completeness, space complexity, and interactive proofs.',
            'Covers the mathematical foundations of cryptography including symmetric encryption, public-key cryptography, digital signatures, and cryptographic protocols.',
            'An introduction to graph theory and algorithms covering shortest paths, minimum spanning trees, network flow, and applications in combinatorial optimisation.',
            'Develops the theory of formal languages and automata, covering regular languages, context-free grammars, Turing machines, and decidability.',
        ],
    },

    {
        name   => 'Artificial Intelligence and Machine Learning',
        titles => [
            'Artificial Intelligence',
            'Deep Learning',
            'Natural Language Processing',
            'Computer Vision',
            'Reinforcement Learning',
        ],
        subtitles => [
            'A Modern Approach',
            'Architectures and Applications',
            'With Neural Networks',
            'From Pixels to Understanding',
            'An Introduction',
        ],
        authors => [
            'Zhang, Xiaoming',
            'Andersen, Signe K.',
            'Okonkwo, Emeka C.',
            'Beaumont, Isabelle',
            'Krishnamurthy, Venkat',
        ],
        subjects => [
            'Artificial intelligence',
            'Machine learning',
            'Deep learning',
            'Natural language processing (Computer science)',
            'Computer vision',
            'Neural networks (Computer science)',
        ],
        geo_subjects      => [ 'United States', 'China', 'Canada' ],
        personal_subjects => [
            'Turing, Alan Mathison, 1912-1954',
            'LeCun, Yann',
            'Hinton, Geoffrey',
        ],
        corp_subjects => [
            'Google (Firm)',
            'OpenAI',
            'DeepMind Technologies',
        ],
        form_genres   => [ 'Textbooks', 'Conference proceedings', 'Technical reports' ],
        variant_forms => {
            'Artificial intelligence' => [ 'AI', 'Machine intelligence', 'Computational intelligence' ],
            'Machine learning'        => [ 'Statistical machine learning', 'Automated learning' ],
            'Deep learning'           => [ 'Deep neural networks', 'Representation learning' ],
        },
        summaries   => [
            'A comprehensive introduction to artificial intelligence covering search, knowledge representation, probabilistic reasoning, machine learning, and robotics.',
            'Covers deep neural networks from perceptrons to convolutional and recurrent architectures, with applications in image recognition and language modelling.',
            'An in-depth treatment of natural language processing covering tokenisation, parsing, sequence-to-sequence models, and large language model architectures.',
            'Introduces computer vision algorithms for image classification, object detection, semantic segmentation, and 3D scene reconstruction.',
            'A foundational treatment of reinforcement learning covering Markov decision processes, temporal difference learning, policy gradients, and deep RL.',
        ],
    },

    {
        name   => 'Systems and Networks',
        titles => [
            'Operating Systems',
            'Computer Networks',
            'Distributed Systems',
            'Computer Security',
            'Cloud Computing',
        ],
        subtitles => [
            'Internals and Design Principles',
            'A Top-Down Approach',
            'Principles and Paradigms',
            'Principles and Practice',
            'Architecture and Design',
        ],
        authors => [
            'Novak, Tomáš',
            'Obi, Chioma',
            'Lindqvist, Johan',
            'Ferreira, António',
            'Park, Jae-Won',
        ],
        subjects => [
            'Operating systems (Computers)',
            'Computer networks',
            'Distributed computing',
            'Computer security',
            'Cloud computing',
            'Internet of things',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Germany' ],
        personal_subjects => [
            'Dijkstra, E. W. (Edsger Wybe), 1930-2002',
            'Cerf, Vinton G.',
            'Lampson, Butler W.',
        ],
        corp_subjects => [
            'Internet Engineering Task Force',
            'Linux Foundation',
            'IEEE Communications Society',
        ],
        form_genres => [ 'Textbooks', 'Handbooks, manuals, etc.', 'Standards' ],
        summaries   => [
            'A thorough treatment of operating system design covering processes, threads, memory management, file systems, and I/O, with case studies from Linux and Windows.',
            'Introduces computer networking from the physical layer through application protocols, covering TCP/IP, routing algorithms, and network security.',
            'A comprehensive study of distributed systems covering communication, naming, synchronisation, consistency and replication, and fault tolerance.',
            'Covers the principles and practice of computer security including authentication, access control, cryptographic protocols, and vulnerability analysis.',
            'Explores cloud computing architectures, virtualisation, container orchestration, serverless computing, and cloud-native application design.',
        ],
    },

    {
        name   => 'Electrical and Electronic Engineering',
        titles => [
            'Circuit Theory',
            'Digital Signal Processing',
            'Microelectronics',
            'Power Systems Engineering',
            'Control Systems',
        ],
        subtitles => [
            'Analysis and Design',
            'Theory and Applications',
            'Devices and Circuits',
            'Analysis and Design',
            'Classical and Modern Approaches',
        ],
        authors => [
            'Morales, Diego',
            'Harada, Satoshi',
            'Ndegwa, Peter',
            'Vassiliev, Andrei',
            'Thornton, Rebecca J.',
        ],
        subjects => [
            'Electric circuits',
            'Signal processing',
            'Semiconductors',
            'Electric power systems',
            'Automatic control',
            'Electronics',
        ],
        geo_subjects      => [ 'United States', 'Japan', 'Germany' ],
        personal_subjects => [
            'Maxwell, James Clerk, 1831-1879',
            'Tesla, Nikola, 1856-1943',
            'Shannon, Claude Elwood, 1916-2001',
        ],
        corp_subjects => [
            'Institute of Electrical and Electronics Engineers',
            'Intel Corporation',
            'Siemens AG',
        ],
        form_genres => [ 'Textbooks', 'Handbooks, manuals, etc.', 'Problem sets' ],
        summaries   => [
            'A thorough introduction to circuit analysis covering KVL, KCL, phasors, AC circuits, frequency response, and two-port networks.',
            'Covers digital signal processing from the discrete Fourier transform through filter design, spectral analysis, and multirate systems.',
            'An introduction to microelectronics covering semiconductor physics, diodes, bipolar and MOS transistors, and amplifier design.',
            'Comprehensive treatment of electric power systems covering generation, transmission, distribution, load flow analysis, and power system stability.',
            'Introduces control systems theory covering transfer functions, feedback, stability analysis using Bode and root locus methods, and state-space design.',
        ],
    },

    {
        name   => 'Mechanical and Aerospace Engineering',
        titles => [
            'Engineering Mechanics',
            'Fluid Mechanics',
            'Aerodynamics',
            'Robotics',
            'Heat Transfer',
        ],
        subtitles => [
            'Statics and Dynamics',
            'Fundamentals and Applications',
            'For Engineers and Scientists',
            'Modelling and Control',
            'Conduction, Convection, and Radiation',
        ],
        authors => [
            'Schäfer, Hans',
            'Olumide, Festus',
            'Nakashima, Taro',
            'Bortolini, Marco',
            'Christensen, Poul E.',
        ],
        subjects => [
            'Mechanics, Applied',
            'Fluid mechanics',
            'Aerodynamics',
            'Robotics',
            'Heat transfer',
            'Mechanical engineering',
        ],
        geo_subjects      => [ 'Germany', 'United States', 'Japan' ],
        personal_subjects => [
            'von Kármán, Theodore, 1881-1963',
            'Wright, Orville, 1871-1948',
            'Prandtl, Ludwig, 1875-1953',
        ],
        corp_subjects => [
            'American Society of Mechanical Engineers',
            'American Institute of Aeronautics and Astronautics',
            'Deutsche Luft- und Raumfahrt',
        ],
        form_genres => [ 'Textbooks', 'Handbooks, manuals, etc.', 'Conference proceedings' ],
        summaries   => [
            'Covers the fundamentals of engineering mechanics including statics of rigid bodies, kinematics, energy methods, and vibrations.',
            'A comprehensive treatment of fluid mechanics covering fluid statics, viscous flows, boundary layers, and turbulence.',
            'Introduces aerodynamics covering subsonic and supersonic flow, aerofoil theory, wing aerodynamics, and compressible flow phenomena.',
            'Covers robot kinematics, dynamics, trajectory planning, and control, with discussion of manipulator design and autonomous systems.',
            'A thorough treatment of heat transfer by conduction, convection, and radiation, with applications in heat exchangers and thermal system design.',
        ],
    },

    {
        name   => 'Civil and Environmental Engineering',
        titles => [
            'Structural Analysis',
            'Soil Mechanics',
            'Water Resources Engineering',
            'Transportation Engineering',
            'Environmental Engineering',
        ],
        subtitles => [
            'Determinate and Indeterminate Structures',
            'Principles and Practice',
            'Hydrology and Hydraulics',
            'Planning and Design',
            'Water, Wastewater, and Air',
        ],
        authors => [
            'Johansson, Sven',
            'Mensah, Kojo',
            'Tanaka, Hiroshi',
            'Ramirez, Carlos',
            'Ekwueme, Ugochukwu',
        ],
        subjects => [
            'Structural analysis (Engineering)',
            'Soil mechanics',
            'Hydraulic engineering',
            'Transportation engineering',
            'Environmental engineering',
            'Earthquake engineering',
        ],
        geo_subjects      => [ 'United States', 'Japan', 'Netherlands' ],
        personal_subjects => [
            'Terzaghi, Karl, 1883-1963',
            'Maillart, Robert, 1872-1940',
            'Rankine, W. J. M. (William John Macquorn), 1820-1872',
        ],
        corp_subjects => [
            'American Society of Civil Engineers',
            'Institution of Civil Engineers (Great Britain)',
            'World Road Association',
        ],
        form_genres => [ 'Textbooks', 'Design guides', 'Case studies' ],
        summaries   => [
            'A systematic introduction to structural analysis covering statically determinate and indeterminate beams, frames, and trusses using the stiffness method.',
            'Introduces the fundamentals of soil mechanics including classification, compaction, permeability, consolidation, shear strength, and slope stability.',
            'Covers hydrological principles and hydraulic engineering including open channel flow, pipe networks, groundwater, and flood estimation.',
            'An introduction to transportation engineering covering highway design, traffic flow theory, intersection control, and public transit planning.',
            'A comprehensive treatment of environmental engineering covering water and wastewater treatment, air pollution control, and solid waste management.',
        ],
    },

    {
        name   => 'Biomedical Engineering',
        titles => [
            'Introduction to Biomedical Engineering',
            'Medical Imaging',
            'Biomechanics',
            'Bioinformatics',
            'Neural Engineering',
        ],
        subtitles => [
            'Principles and Applications',
            'Technology and Clinical Applications',
            'Analysis of Biological Tissues',
            'Sequence Analysis and Structural Biology',
            'Brain-Computer Interfaces',
        ],
        authors => [
            'Oluwafemi, Adebola',
            'Lindgren, Maja',
            'Kobayashi, Eri',
            'Ndiaye, Mamadou',
            'Wallace, Duncan T.',
        ],
        subjects => [
            'Biomedical engineering',
            'Diagnostic imaging',
            'Biomechanics',
            'Bioinformatics',
            'Neural interfaces',
            'Tissue engineering',
        ],
        geo_subjects      => [ 'United States', 'Germany', 'Sweden' ],
        personal_subjects => [
            'Hounsfield, Godfrey Newbold, 1919-2004',
            'Damadian, Raymond',
            'Cormack, Allan M., 1924-1998',
        ],
        corp_subjects => [
            'Biomedical Engineering Society',
            'National Institutes of Health (U.S.)',
            'European Society for Biomechanics',
        ],
        form_genres => [ 'Textbooks', 'Review articles', 'Case studies' ],
        summaries   => [
            'A broad introduction to biomedical engineering covering biomechanics, biomaterials, biosignal processing, medical imaging, and tissue engineering.',
            'Comprehensive coverage of medical imaging modalities including X-ray, CT, MRI, PET, and ultrasound, emphasising physical and mathematical principles.',
            'Covers the mechanics of biological tissues, joints, and movement, with applications in orthopaedic implant design and injury biomechanics.',
            'An introduction to bioinformatics covering sequence alignment, database searching, phylogenetics, and structural bioinformatics.',
            'Explores the principles and applications of neural engineering, including electrode design, signal processing, and brain-computer interface systems.',
        ],
    },

    {
        name   => 'Energy Technology',
        titles => [
            'Renewable Energy',
            'Solar Cell Technology',
            'Wind Energy',
            'Nuclear Engineering',
            'Energy Storage Systems',
        ],
        subtitles => [
            'Physics and Engineering',
            'Photovoltaic Principles',
            'Technology and Applications',
            'Reactor Design and Safety',
            'Batteries and Beyond',
        ],
        authors => [
            'Andersen, Niels',
            'Onyeka, Bola',
            'Tanigawa, Yutaka',
            'Johansson, Anders M.',
            'Papagiannopoulos, Alexandros',
        ],
        subjects => [
            'Renewable energy sources',
            'Solar energy',
            'Wind power',
            'Nuclear engineering',
            'Energy storage',
            'Smart power grids',
        ],
        geo_subjects      => [ 'Denmark', 'Germany', 'China' ],
        personal_subjects => [
            'Becquerel, Edmond, 1820-1891',
            'Einstein, Albert, 1879-1955',
            'Fermi, Enrico, 1901-1954',
        ],
        corp_subjects => [
            'International Energy Agency',
            'European Renewable Energy Council',
            'International Atomic Energy Agency',
        ],
        form_genres => [ 'Textbooks', 'Technical reports', 'Case studies' ],
        summaries   => [
            'A comprehensive introduction to renewable energy technologies including solar, wind, hydropower, and geothermal, covering resource assessment and system design.',
            'Covers the physics and technology of photovoltaic solar cells, from semiconductor fundamentals to module design and grid-connected systems.',
            'An introduction to wind energy technology covering aerodynamics, turbine design, siting, and the integration of wind power into electricity grids.',
            'A thorough treatment of nuclear engineering covering reactor physics, neutron transport, thermal hydraulics, and reactor safety systems.',
            'Covers electrochemical energy storage including lithium-ion batteries, redox flow batteries, fuel cells, and supercapacitors.',
        ],
    },

    # === HUMANITIES ===

    {
        name   => 'Ancient and Medieval History',
        titles => [
            'The Ancient World',
            'Rome and Its Empire',
            'The Byzantine Empire',
            'Medieval Europe',
            'The Silk Road',
        ],
        subtitles => [
            'Egypt, Greece, and the Near East',
            'From Republic to Fall',
            'A History',
            'Society, Economy, and Culture',
            'Trade, Travel, and Cultural Exchange',
        ],
        authors => [
            'Blackwood, Margaret',
            'Papadopoulos, Nikos',
            'Al-Rashid, Omar',
            'Christodoulou, Elena',
            'Müller, Friedrich',
        ],
        subjects => [
            'History, Ancient',
            'Rome (Empire)',
            'Byzantine Empire--History',
            'Middle Ages',
            'Silk Road',
            'Feudalism',
        ],
        geo_subjects      => [ 'Mediterranean Region', 'Turkey', 'Middle East' ],
        personal_subjects => [
            'Caesar, Julius',
            'Justinian I, Emperor of the East, 483?-565',
            'Charlemagne, Emperor, 742-814',
        ],
        corp_subjects => [
            'Roman Catholic Church',
            'Holy Roman Empire',
            'Byzantine Empire',
        ],
        form_genres   => [ 'History', 'Biographies', 'Sourcebooks' ],
        variant_forms => {
            'Rome (Empire)'             => [ 'Roman Empire', 'Imperium Romanum', 'Roman civilization' ],
            'History, Ancient'          => [ 'Ancient history', 'Classical antiquity' ],
            'Byzantine Empire--History' => [ 'Eastern Roman Empire', 'Byzantium' ],
            'Mediterranean Region'      => [ 'Mediterranean world', 'Mediterranean lands' ],
        },
        summaries   => [
            'A sweeping survey of the ancient world from the early civilisations of Mesopotamia and Egypt through the classical Greek and Roman periods, with attention to culture, politics, and society.',
            'A comprehensive history of the Roman Empire covering the Augustan settlement, provincial administration, the third-century crisis, and the transformation into the medieval world.',
            'An authoritative account of the Byzantine Empire from its foundation to the fall of Constantinople in 1453, examining politics, religion, art, and diplomacy.',
            'Examines medieval European society covering feudal structures, the church, urban development, intellectual life, and the crises of the fourteenth century.',
            'Explores the Silk Road as a network of trade, religion, and cultural exchange connecting East Asia, Central Asia, the Middle East, and Europe.',
        ],
    },

    {
        name   => 'Early Modern and Modern History',
        titles => [
            'The Renaissance',
            'The Reformation in Europe',
            'European Colonialism',
            'The Industrial Revolution',
            'Nationalism and the Nation-State',
        ],
        subtitles => [
            'Art, Culture, and Thought',
            'Religion, Politics, and Society',
            'Empire, Race, and Resistance',
            'Technology, Society, and Global Change',
            'Europe in the Long Nineteenth Century',
        ],
        authors => [
            'Fontaine, Pierre',
            'Osei, Kwaku',
            'Svensson, Britta',
            'O\'Brien, Cathal',
            'Hartmann, Wolfgang',
        ],
        subjects => [
            'Renaissance',
            'Reformation',
            'Colonialism',
            'Industrial revolution',
            'Nationalism',
            'History, Modern',
        ],
        geo_subjects      => [ 'Europe', 'Italy', 'Great Britain' ],
        personal_subjects => [
            'Luther, Martin, 1483-1546',
            'Machiavelli, Niccolò, 1469-1527',
            'Napoleon I, Emperor of the French, 1769-1821',
        ],
        corp_subjects => [
            'Catholic Church',
            'East India Company (English)',
            'Protestant churches',
        ],
        form_genres   => [ 'History', 'Essays', 'Sourcebooks' ],
        variant_forms => {
            'Nationalism'           => [ 'National identity', 'Nation-states', 'Nationhood' ],
            'Industrial revolution' => [ 'Industrialisation', 'Industrial age', 'Industrial transformation' ],
            'Colonialism'           => [ 'Colonial rule', 'European colonialism', 'Imperialism' ],
        },
        summaries   => [
            'A study of the Italian Renaissance covering humanism, artistic innovation, political thought, and the recovery and transmission of classical learning across Europe.',
            'Traces the origins, spread, and consequences of the Protestant Reformation, examining Luther, Calvin, and the political and social transformations wrought by religious division.',
            'A critical history of European colonial expansion from the fifteenth century, examining the subjugation of indigenous peoples, plantation slavery, and the legacies of empire.',
            'Examines the Industrial Revolution in Britain and its global spread, covering technological change, labour conditions, urbanisation, and transformation of the world economy.',
            'Analyses the rise of nationalism in the nineteenth century and its role in the unification of Germany and Italy, the dissolution of empires, and redrawing of European boundaries.',
        ],
    },

    {
        name   => 'Twentieth-Century History',
        titles => [
            'The First World War',
            'The Second World War',
            'The Cold War',
            'Decolonisation in Africa and Asia',
            'The Civil Rights Movement',
        ],
        subtitles => [
            'A Global History',
            'Military and Diplomatic History',
            'A Global History',
            'Independence and Its Aftermath',
            'From Montgomery to Memphis',
        ],
        authors => [
            'Williams, Trevor',
            'Müller, Hannah',
            'Adeyemi, Femi',
            'Marchetti, Anna',
            'Washington, Gregory T.',
        ],
        subjects => [
            'World War, 1914-1918',
            'World War, 1939-1945',
            'Cold War',
            'Decolonization',
            'Civil rights movements',
            'History, Modern--20th century',
        ],
        geo_subjects      => [ 'Europe', 'Africa', 'United States' ],
        personal_subjects => [
            'Hitler, Adolf, 1889-1945',
            'Churchill, Winston, 1874-1965',
            'King, Martin Luther, Jr., 1929-1968',
        ],
        corp_subjects => [
            'United Nations',
            'North Atlantic Treaty Organization',
            'Nazi Party (Germany)',
        ],
        form_genres   => [ 'History', 'Biographies', 'Documentary films' ],
        variant_forms => {
            'Cold War'             => [ 'East-West conflict', 'Soviet-American rivalry', 'Cold War era' ],
            'World War, 1939-1945' => [ 'Second World War', 'World War II', 'WWII' ],
            'World War, 1914-1918' => [ 'First World War', 'World War I', 'Great War' ],
        },
        summaries   => [
            'A comprehensive history of the First World War examining its origins in European power politics, the conduct of military operations, and its revolutionary consequences for world order.',
            'A global history of the Second World War covering military operations, occupation regimes, genocide, and the political and social consequences of the conflict.',
            'Examines the Cold War from the end of the Second World War to the collapse of the Soviet Union, covering ideology, nuclear strategy, and proxy conflicts worldwide.',
            'Analyses decolonisation in Africa and Asia after 1945, examining independence movements, the transition to statehood, and the challenges of post-colonial development.',
            'A study of the American civil rights movement covering the legal, political, and social struggle for racial equality from the mid-1950s through landmark legislation of the 1960s.',
        ],
    },

    {
        name   => 'Philosophy: Metaphysics and Epistemology',
        titles => [
            'Introduction to Metaphysics',
            'Theory of Knowledge',
            'Consciousness and the Mind',
            'The Problem of Free Will',
            'Philosophy of Time and Space',
        ],
        subtitles => [
            'Being, Identity, and Reality',
            'An Epistemological Introduction',
            'The Hard Problem',
            'Determinism and Moral Responsibility',
            'Ontology and Physics',
        ],
        authors => [
            'Hoffmann, Ursula',
            'MacNeil, Alasdair J.',
            'Tanaka, Fumiko',
            'Olawale, Remi',
            'Petit, François',
        ],
        subjects => [
            'Metaphysics',
            'Knowledge, Theory of',
            'Consciousness',
            'Free will and determinism',
            'Space and time',
            'Ontology',
        ],
        geo_subjects      => [ 'Germany', 'Greece', 'France' ],
        personal_subjects => [
            'Kant, Immanuel, 1724-1804',
            'Descartes, René, 1596-1650',
            'Heidegger, Martin, 1889-1976',
        ],
        corp_subjects => [
            'American Philosophical Association',
            'British Philosophical Association',
            'Aristotelian Society',
        ],
        form_genres   => [ 'Textbooks', 'Monographs', 'Essays' ],
        variant_forms => {
            'Consciousness'             => [ 'Mind', 'Sentience', 'Subjective experience', 'Awareness' ],
            'Knowledge, Theory of'      => [ 'Epistemology', 'Theory of knowledge' ],
            'Free will and determinism' => [ 'Free will', 'Determinism', 'Compatibilism' ],
        },
        summaries   => [
            'A systematic introduction to metaphysics covering the nature of existence, substance, causation, personal identity, and the relationship between mind and matter.',
            'Introduces the central problems of epistemology including the nature and sources of knowledge, scepticism, justification, and the analysis of belief.',
            'Explores philosophical approaches to consciousness and the mind, examining functionalism, physicalism, dualism, and the explanatory gap between brain and subjective experience.',
            'A thorough examination of the free will debate, covering determinism, compatibilism, libertarianism, and the implications for moral responsibility.',
            'Examines philosophical questions about the nature of time and space, including debates between absolutism and relationalism and the metaphysics of temporal passage.',
        ],
    },

    {
        name   => 'Philosophy: Ethics and Political Thought',
        titles => [
            'Ethics: An Introduction',
            'Political Philosophy',
            'Justice',
            'Applied Ethics',
            'Human Rights',
        ],
        subtitles => [
            'Theories of Moral Life',
            'From Plato to Rawls',
            'What Is Owed to Each Other',
            'Medicine, Law, and Technology',
            'Philosophy and Politics',
        ],
        authors => [
            'Osei, Yaw',
            'Lindberg, Kerstin',
            'Nakajima, Yoko',
            'Martins, Diogo',
            'Sullivan, Eileen',
        ],
        subjects => [
            'Ethics',
            'Political philosophy',
            'Justice (Philosophy)',
            'Applied ethics',
            'Human rights',
            'Social contract',
        ],
        geo_subjects      => [ 'Great Britain', 'United States', 'France' ],
        personal_subjects => [
            'Rawls, John, 1921-2002',
            'Mill, John Stuart, 1806-1873',
            'Aristotle, 384-322 B.C.',
        ],
        corp_subjects => [
            'United Nations. General Assembly',
            'Amnesty International',
            'International Criminal Court',
        ],
        form_genres   => [ 'Textbooks', 'Monographs', 'Sourcebooks' ],
        variant_forms => {
            'Ethics'               => [ 'Moral philosophy', 'Morality', 'Moral theory' ],
            'Political philosophy' => [ 'Political theory', 'Political thought' ],
            'Human rights'         => [ 'Fundamental rights', 'Basic rights', 'Civil liberties' ],
        },
        summaries   => [
            'A comprehensive introduction to ethical theory covering utilitarianism, deontology, virtue ethics, and contractarianism, with discussion of contemporary moral problems.',
            'A survey of political philosophy from ancient Greece to the present, examining key texts and debates about justice, authority, liberty, equality, and democracy.',
            'An examination of theories of distributive justice covering Rawls theory of justice, libertarianism, luck egalitarianism, and the capabilities approach.',
            'Applies ethical reasoning to contemporary problems in bioethics, business ethics, environmental ethics, and digital technology.',
            'A philosophical examination of human rights covering their foundations, content, enforcement, and tensions between universalism and cultural difference.',
        ],
    },

    {
        name   => 'English and World Literature',
        titles => [
            'The English Novel',
            'Shakespeare: A Critical Study',
            'Postcolonial Fiction',
            'Poetry and Poetics',
            'World Literature in Translation',
        ],
        subtitles => [
            'From Defoe to the Present',
            'Plays, Poems, and Contexts',
            'Narrative, Nation, and Identity',
            'Theory and Practice',
            'A Reader\'s Companion',
        ],
        authors => [
            'Hartley, Patricia M.',
            'Adichie, Chukwuemeka',
            'Morrison, Janet',
            'Gupta, Ananya',
            'Dupont, Marguerite',
        ],
        subjects => [
            'English literature',
            'American literature',
            'Postcolonial literature',
            'Narrative theory',
            'Poetry',
            'Fiction',
        ],
        geo_subjects      => [ 'Great Britain', 'United States', 'Nigeria' ],
        personal_subjects => [
            'Shakespeare, William, 1564-1616',
            'Joyce, James, 1882-1941',
            'Woolf, Virginia, 1882-1941',
        ],
        corp_subjects => [
            'British Council',
            'Booker Prize',
            'Academy of American Poets',
        ],
        form_genres => [ 'Literary criticism', 'Anthologies', 'Translations' ],
        summaries   => [
            'A critical survey of the English novel from its origins in the eighteenth century through the modernist and postmodernist periods, with close readings of canonical and neglected texts.',
            'An introduction to Shakespeare plays and poetry, covering the major tragedies, comedies, and histories, with attention to textual history, performance, and critical reception.',
            'Examines postcolonial fiction from Africa, Asia, and the Caribbean, exploring how novelists engage with colonial history, cultural identity, and the legacies of imperialism.',
            'Introduces the theory and practice of poetry, covering prosody, form, imagery, and voice, with close readings of poems from the Romantic period to the present.',
            'A reader guide to world literature in English translation, covering novels, stories, and poetry from Latin America, Europe, Africa, and Asia.',
        ],
    },

    {
        name   => 'Linguistics',
        titles => [
            'An Introduction to Linguistics',
            'Syntax',
            'Semantics',
            'Phonology',
            'Sociolinguistics',
        ],
        subtitles => [
            'The Study of Language',
            'A Minimalist Approach',
            'Meaning, Truth, and Reference',
            'Sound Patterns in Language',
            'Language and Society',
        ],
        authors => [
            'Nilsson, Lars E.',
            'Okafor, Adaobi',
            'Dubois, Sylvie',
            'Tanaka, Naomi',
            'Castro, Felipe',
        ],
        subjects => [
            'Linguistics',
            'Grammar, Comparative and general--Syntax',
            'Semantics',
            'Phonology',
            'Sociolinguistics',
            'Language acquisition',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Africa' ],
        personal_subjects => [
            'Chomsky, Noam',
            'Saussure, Ferdinand de, 1857-1913',
            'Labov, William',
        ],
        corp_subjects => [
            'Linguistic Society of America',
            'International Linguistic Association',
            'Summer Institute of Linguistics',
        ],
        form_genres => [ 'Textbooks', 'Monographs', 'Language surveys' ],
        summaries   => [
            'A broad introduction to linguistics covering phonetics, phonology, morphology, syntax, semantics, pragmatics, and language acquisition.',
            'A systematic introduction to syntactic theory covering phrase structure, movement operations, binding theory, and the minimalist programme.',
            'Examines meaning in natural language, covering compositionality, reference, quantification, presupposition, and conversational implicature.',
            'An introduction to phonological theory covering phonemes, distinctive features, syllable structure, and prosodic phonology.',
            'Explores the relationship between language and society, covering language variation, language change, multilingualism, and language policy.',
        ],
    },

    {
        name   => 'Art History and Visual Culture',
        titles => [
            'A History of Art',
            'Renaissance Art in Italy',
            'Impressionism',
            'Modern Art',
            'Photography',
        ],
        subtitles => [
            'From Prehistory to the Present',
            'Painting, Sculpture, Architecture',
            'Origins and Influence',
            'A Critical Introduction',
            'A Cultural History',
        ],
        authors => [
            'Bauer, Christina',
            'Moretti, Alessandro',
            'Leclerc, Nathalie',
            'Adeyemi, Taiwo',
            'Sandström, Karin',
        ],
        subjects => [
            'Art history',
            'Renaissance art',
            'Impressionism (Art)',
            'Art, Modern',
            'Photography--History',
            'Architecture',
        ],
        geo_subjects      => [ 'Italy', 'France', 'New York (State)' ],
        personal_subjects => [
            'Leonardo, da Vinci, 1452-1519',
            'Monet, Claude, 1840-1926',
            'Picasso, Pablo, 1881-1973',
        ],
        corp_subjects => [
            'Musée du Louvre',
            'Metropolitan Museum of Art',
            'Uffizi (Gallery)',
        ],
        form_genres => [ 'Art catalogs', 'Textbooks', 'Illustrated works' ],
        summaries   => [
            'A comprehensive survey of Western art from cave painting through classical antiquity, the Middle Ages, Renaissance, Baroque, and into the modern and contemporary periods.',
            'An in-depth study of Italian Renaissance painting, sculpture, and architecture, covering the major masters and regional schools of Florence, Venice, and Rome.',
            'Traces the origins of Impressionism in the Paris of the 1860s, its development and internal tensions, and its influence on Post-Impressionism and modern art.',
            'A critical introduction to modern art from the Post-Impressionists through Cubism, Expressionism, Surrealism, Abstract Expressionism, and Conceptual art.',
            'A cultural history of photography from its invention in the 1830s to the digital present, examining its role in documentary, art, and the construction of visual culture.',
        ],
    },

    # === SOCIAL SCIENCES ===

    {
        name   => 'Psychology',
        titles => [
            'Cognitive Psychology',
            'Developmental Psychology',
            'Clinical Psychology',
            'Social Psychology',
            'Neuropsychology',
        ],
        subtitles => [
            'Mind, Brain, and Behaviour',
            'From Infancy to Adulthood',
            'Theory and Practice',
            'Understanding Human Behaviour',
            'Disorders and Rehabilitation',
        ],
        authors => [
            'Bergström, Eva M.',
            'Adeyemi, Funmilayo',
            'Kowalski, Joanna',
            'Park, Sangwon',
            'Mitchell, David R.',
        ],
        subjects => [
            'Psychology',
            'Cognitive psychology',
            'Developmental psychology',
            'Clinical psychology',
            'Social psychology',
            'Neuropsychology',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Sweden' ],
        personal_subjects => [
            'Freud, Sigmund, 1856-1939',
            'Piaget, Jean, 1896-1980',
            'Bandura, Albert, 1925-',
        ],
        corp_subjects => [
            'American Psychological Association',
            'British Psychological Society',
            'World Health Organization',
        ],
        form_genres => [ 'Textbooks', 'Case studies', 'Research reports' ],
        summaries   => [
            'A comprehensive introduction to cognitive psychology covering perception, attention, memory, language, problem-solving, and decision-making, drawing on experimental and neuroscientific research.',
            'Covers human development from prenatal stages through childhood, adolescence, and adult development, integrating biological, cognitive, and sociocultural perspectives.',
            'An introduction to clinical psychology covering psychopathology, psychological assessment, and evidence-based therapies including CBT, psychodynamic, and systemic approaches.',
            'Examines social behaviour and cognition, covering social perception, attitudes, conformity, obedience, group dynamics, and intergroup relations.',
            'An introduction to neuropsychology covering brain structure, functional lateralisation, neurological disorders, and neuropsychological assessment.',
        ],
    },

    {
        name   => 'Sociology and Criminology',
        titles => [
            'Introduction to Sociology',
            'Social Stratification',
            'Urban Sociology',
            'Criminology',
            'Globalisation and Society',
        ],
        subtitles => [
            'A Critical Approach',
            'Class, Race, and Gender',
            'Cities, Space, and Society',
            'Theories and Methods',
            'Social Change in a Borderless World',
        ],
        authors => [
            'Harrison, Jane M.',
            'Osei, Emmanuel',
            'López, Carmen R.',
            'Johansson, Ingrid K.',
            'Ikenna, Chibuike',
        ],
        subjects => [
            'Sociology',
            'Social stratification',
            'Urban sociology',
            'Criminology',
            'Globalization',
            'Social change',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'China' ],
        personal_subjects => [
            'Giddens, Anthony',
            'Bourdieu, Pierre, 1930-2002',
            'Foucault, Michel, 1926-1984',
        ],
        corp_subjects => [
            'American Sociological Association',
            'British Sociological Association',
            'United Nations',
        ],
        form_genres => [ 'Textbooks', 'Case studies', 'Statistical data' ],
        summaries   => [
            'A broad introduction to sociological concepts and theory covering social structure, culture, inequality, organisations, and social change, with attention to contemporary debates.',
            'Examines social inequality through the dimensions of class, race, ethnicity, and gender, exploring theories of stratification and the empirical dimensions of inequality.',
            'An introduction to urban sociology covering urbanisation, city structure, residential segregation, neighbourhood dynamics, and the effects of globalisation on cities.',
            'A comprehensive introduction to criminology covering theories of crime, criminal justice systems, policing, sentencing, and contemporary issues in crime prevention.',
            'Examines globalisation as a social, economic, and cultural phenomenon, covering global networks, migration, inequality, and challenges to national sovereignty.',
        ],
    },

    {
        name   => 'Economics',
        titles => [
            'Principles of Economics',
            'Macroeconomics',
            'Behavioural Economics',
            'Development Economics',
            'Financial Economics',
        ],
        subtitles => [
            'Microeconomics and Macroeconomics',
            'Theories, Policies, and Models',
            'Psychology and Economic Decision-Making',
            'Growth, Poverty, and Institutions',
            'Markets, Risk, and Return',
        ],
        authors => [
            'Nwachukwu, Ikenna',
            'Andersen, Niels P.',
            'Christodoulou, Spyros',
            'Kimura, Hiromi',
            'Fernández, Jorge',
        ],
        subjects => [
            'Economics',
            'Macroeconomics',
            'Behavioral economics',
            'Economic development',
            'Finance',
            'Labor economics',
        ],
        geo_subjects      => [ 'United States', 'Africa', 'European Union countries' ],
        personal_subjects => [
            'Keynes, John Maynard, 1883-1946',
            'Smith, Adam, 1723-1790',
            'Friedman, Milton, 1912-2006',
        ],
        corp_subjects => [
            'International Monetary Fund',
            'World Bank',
            'Organisation for Economic Co-operation and Development',
        ],
        form_genres => [ 'Textbooks', 'Monographs', 'Working papers' ],
        summaries   => [
            'A comprehensive introduction to economic principles covering supply and demand, market structure, national income accounting, monetary policy, and international trade.',
            'An advanced treatment of macroeconomics covering growth theory, business cycle models, monetary and fiscal policy, and open economy macroeconomics.',
            'Introduces behavioural economics, examining how psychological biases and heuristics lead to departures from rational choice, with implications for policy design.',
            'Examines the economics of development, covering growth theory, poverty traps, institutions, health, education, and the political economy of development.',
            'A rigorous treatment of financial economics covering portfolio theory, asset pricing, corporate finance, derivatives pricing, and market microstructure.',
        ],
    },

    {
        name   => 'Political Science',
        titles => [
            'Introduction to Political Science',
            'Comparative Politics',
            'International Relations',
            'Public Policy',
            'Democratic Theory',
        ],
        subtitles => [
            'The State, Power, and Government',
            'Systems, Parties, and Policy',
            'Theories and Global Issues',
            'Processes and Outcomes',
            'From Ancient Athens to the Present',
        ],
        authors => [
            "O'Donnell, Siobhán",
            'Mensah, Kwabena',
            'Lindqvist, Per',
            'Nakamura, Tetsuro',
            'Petrov, Dmitri V.',
        ],
        subjects => [
            'Political science',
            'Comparative government',
            'International relations',
            'Public policy',
            'Democracy',
            'Geopolitics',
        ],
        geo_subjects      => [ 'Europe', 'United States', 'Middle East' ],
        personal_subjects => [
            'Machiavelli, Niccolò, 1469-1527',
            'Hobbes, Thomas, 1588-1679',
            'Rousseau, Jean-Jacques, 1712-1778',
        ],
        corp_subjects => [
            'United Nations',
            'European Union',
            'North Atlantic Treaty Organization',
        ],
        form_genres => [ 'Textbooks', 'Case studies', 'Sourcebooks' ],
        summaries   => [
            'An introduction to political science covering the state, power, legitimacy, democratic and authoritarian regimes, and the major traditions of political thought.',
            'A systematic study of comparative politics examining electoral systems, party systems, coalitions, constitutional design, and policy outcomes across democracies.',
            'Covers the major theories of international relations — realism, liberalism, constructivism — and applies them to contemporary global issues.',
            'An introduction to public policy covering agenda setting, policy formulation, implementation, and evaluation, with case studies from health, education, and environment.',
            'A philosophical and empirical study of democracy, examining democratic theory, the challenges of populism, electoral integrity, and deliberative democracy.',
        ],
    },

    {
        name   => 'Anthropology',
        titles => [
            'Cultural Anthropology',
            'Human Origins',
            'Archaeological Method and Theory',
            'Linguistic Anthropology',
            'Kinship and Social Structure',
        ],
        subtitles => [
            'The Human Challenge',
            'Physical Anthropology and Evolution',
            'Field Methods and Laboratory Techniques',
            'Language, Culture, and Society',
            'Descent, Alliance, and Identity',
        ],
        authors => [
            'Adichie, Nnamdi',
            'Svensson, Karin',
            'Moretti, Elena',
            'Nakajima, Hiroshi',
            'Okafor, Chisom',
        ],
        subjects => [
            'Cultural anthropology',
            'Physical anthropology',
            'Archaeology',
            'Linguistic anthropology',
            'Kinship',
            'Ethnology',
        ],
        geo_subjects      => [ 'Africa', 'Amazon River Region', 'Pacific Area' ],
        personal_subjects => [
            'Boas, Franz, 1858-1942',
            'Lévi-Strauss, Claude, 1908-2009',
            'Malinowski, Bronislaw, 1884-1942',
        ],
        corp_subjects => [
            'American Anthropological Association',
            'Royal Anthropological Institute of Great Britain and Ireland',
            'Society for American Archaeology',
        ],
        form_genres => [ 'Textbooks', 'Ethnographies', 'Case studies' ],
        summaries   => [
            'A comprehensive introduction to cultural anthropology covering research methods, kinship, religion, symbolism, economic systems, and the politics of culture.',
            'Covers physical anthropology from the evolution of primates and hominins through the biological variation of modern humans and human adaptability.',
            'Introduces the methods and theories of archaeology, covering excavation techniques, dating methods, artefact analysis, and the interpretation of past societies.',
            'Explores the relationship between language, thought, and culture, covering language socialisation, code-switching, language ideology, and the ethnography of speaking.',
            'An advanced treatment of kinship theory covering descent, marriage alliance, household organisation, and contemporary debates about kinship and biotechnology.',
        ],
    },

    {
        name   => 'Law',
        titles => [
            'Constitutional Law',
            'International Law',
            'Criminal Law',
            'Contract Law',
            'Human Rights Law',
        ],
        subtitles => [
            'Principles and Practice',
            'Sources, Subjects, and Substance',
            'Text, Cases, and Materials',
            'Theory and Practice',
            'International and European Perspectives',
        ],
        authors => [
            'Blackwood, Fiona A.',
            'Müller, Ludwig',
            'Okonkwo, Adaeze C.',
            'Williams, Gareth',
            'Nakamura, Akiko',
        ],
        subjects => [
            'Constitutional law',
            'International law',
            'Criminal law',
            'Contracts',
            'Human rights',
            'Jurisprudence',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'European Union countries' ],
        personal_subjects => [
            'Hart, H. L. A. (Herbert Lionel Adolphus), 1907-1992',
            'Rawls, John, 1921-2002',
            'Dworkin, Ronald',
        ],
        corp_subjects => [
            'European Court of Human Rights',
            'International Court of Justice',
            'United States Supreme Court',
        ],
        form_genres => [ 'Casebooks', 'Textbooks', 'Law review articles' ],
        summaries   => [
            'A comprehensive study of constitutional law covering the structure of government, federalism, judicial review, individual rights, and constitutional interpretation.',
            'Introduces the sources, principles, and institutions of international law, covering treaties, customary law, the United Nations system, and dispute settlement.',
            'A thorough treatment of criminal law covering the general principles of liability, the mental element, specific offences, defences, and sentencing.',
            'An introduction to contract law covering offer and acceptance, consideration, formation, terms, breach, and remedies, with attention to comparative contract law.',
            'Examines international and European human rights law, covering the major treaties and institutions, substantive rights, and enforcement of human rights obligations.',
        ],
    },

    # === MEDICINE & HEALTH ===

    {
        name   => 'Clinical Medicine',
        titles => [
            'Clinical Cardiology',
            'Oncology',
            'Clinical Neurology',
            'Infectious Disease',
            'Pharmacology',
        ],
        subtitles => [
            'Diagnosis and Management',
            'Principles and Practice',
            'A Practical Guide',
            'Epidemiology and Treatment',
            'Drug Actions and Clinical Use',
        ],
        authors => [
            'Obi, Nwanneka',
            'Lindgren, Karl E.',
            'Watanabe, Fumio',
            'Petrov, Elena',
            'Adewale, Tosin',
        ],
        subjects => [
            'Cardiology',
            'Oncology',
            'Neurology',
            'Communicable diseases',
            'Pharmacology',
            'Internal medicine',
        ],
        geo_subjects      => [ 'United States', 'Sub-Saharan Africa', 'Great Britain' ],
        personal_subjects => [
            'Osler, William, 1849-1919',
            'Fleming, Alexander, 1881-1955',
            'Semmelweis, Ignaz Philipp, 1818-1865',
        ],
        corp_subjects => [
            'World Health Organization',
            'National Health Service (Great Britain)',
            'American College of Cardiology',
        ],
        form_genres => [ 'Textbooks', 'Clinical practice guidelines', 'Case studies' ],
        summaries   => [
            'A comprehensive clinical cardiology text covering coronary artery disease, heart failure, arrhythmias, valvular heart disease, and interventional cardiology.',
            'An evidence-based introduction to oncology covering cancer biology, tumour classification, staging, surgery, radiotherapy, and systemic treatments including immunotherapy.',
            'A practical guide to clinical neurology covering the neurological history and examination, localisation of lesions, and the diagnosis and management of common neurological disorders.',
            'Covers the epidemiology, pathogenesis, diagnosis, and treatment of major infectious diseases including bacterial, viral, fungal, and parasitic infections.',
            'A comprehensive pharmacology textbook covering drug mechanisms, pharmacokinetics, pharmacodynamics, and the major drug classes used in clinical medicine.',
        ],
    },

    {
        name   => 'Public Health and Epidemiology',
        titles => [
            'Epidemiology',
            'Global Health',
            'Public Health',
            'Environmental Health',
            'Health Policy',
        ],
        subtitles => [
            'Principles and Methods',
            'Burden of Disease and Policy Responses',
            'An Introduction',
            'From Local to Global',
            'Analysis and Practice',
        ],
        authors => [
            'Adeyemi, Bisi',
            'Lindstrom, Maria',
            'Tanaka, Rin',
            'Nwosu, Emeka',
            'Beaumont, Jean-Luc',
        ],
        subjects => [
            'Epidemiology',
            'Global health',
            'Public health',
            'Environmental health',
            'Health policy',
            'Disease outbreaks',
        ],
        geo_subjects      => [ 'Africa', 'Asia', 'United States' ],
        personal_subjects => [
            'Snow, John, 1813-1858',
            'Koch, Robert, 1843-1910',
            'Doll, Richard, 1912-2005',
        ],
        corp_subjects => [
            'World Health Organization',
            'Centers for Disease Control and Prevention (U.S.)',
            'Médecins sans Frontières (Association)',
        ],
        form_genres => [ 'Textbooks', 'Research reports', 'Statistical data' ],
        summaries   => [
            'A thorough introduction to epidemiological methods covering study designs, measures of disease frequency and association, bias, confounding, and causal inference.',
            'Examines major global health challenges including infectious and non-communicable diseases, maternal and child health, and the determinants of health inequalities between countries.',
            'A broad introduction to public health covering health promotion, disease prevention, environmental health, health services, and global health governance.',
            'Covers the assessment and control of environmental hazards to health, including air and water pollution, chemical exposures, climate change, and occupational health.',
            'Introduces health policy analysis, covering the political economy of health, healthcare financing, health system design, and evidence-based policy-making.',
        ],
    },

    {
        name   => 'Mental Health',
        titles => [
            'Abnormal Psychology',
            'Psychiatry',
            'Cognitive Behavioural Therapy',
            'Addiction Medicine',
            'Child and Adolescent Mental Health',
        ],
        subtitles => [
            'Understanding and Treating Mental Disorders',
            'A Clinical Textbook',
            'Theory and Practice',
            'Substance Use and Behavioural Addictions',
            'Assessment and Intervention',
        ],
        authors => [
            'Williams, Susan K.',
            'Petrov, Mikhail',
            'Nakamura, Aya',
            'Osei, Josephine',
            'Andersen, Birthe',
        ],
        subjects => [
            'Mental illness',
            'Psychiatry',
            'Cognitive therapy',
            'Substance abuse',
            'Child psychiatry',
            'Depression, Mental',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'Australia' ],
        personal_subjects => [
            'Freud, Sigmund, 1856-1939',
            'Beck, Aaron T.',
            'Kraepelin, Emil, 1856-1926',
        ],
        corp_subjects => [
            'American Psychiatric Association',
            'World Health Organization',
            'National Institute of Mental Health (U.S.)',
        ],
        form_genres => [ 'Textbooks', 'Clinical practice guidelines', 'Case studies' ],
        summaries   => [
            'A comprehensive introduction to abnormal psychology covering the classification, aetiology, assessment, and treatment of the major mental disorders.',
            'A clinical psychiatry textbook covering the diagnosis and management of mood disorders, psychotic disorders, anxiety disorders, and personality disorders.',
            'Provides a thorough grounding in cognitive behavioural therapy covering the theoretical model, assessment procedures, and treatment of depression, anxiety, and other conditions.',
            'A comprehensive treatment of substance use disorders covering the pharmacology of drugs of abuse, the neurobiology of addiction, and evidence-based treatment approaches.',
            'Covers the assessment and treatment of mental health problems in children and adolescents, including ADHD, autism spectrum conditions, anxiety, depression, and eating disorders.',
        ],
    },

    {
        name   => 'Nutrition and Preventive Medicine',
        titles => [
            'Nutrition Science',
            'Clinical Nutrition',
            'Preventive Medicine',
            'Exercise Physiology',
            'The Science of Obesity',
        ],
        subtitles => [
            'From Molecules to Health',
            'Assessment, Support, and Management',
            'A Population Health Perspective',
            'Responses to Physical Activity',
            'Biology, Environment, and Treatment',
        ],
        authors => [
            'Olofsson, Anna-Karin',
            'Nwosu, Chioma',
            'Watanabe, Kei',
            'Andersen, Claus H.',
            "O'Brien, Fiona",
        ],
        subjects => [
            'Nutrition',
            'Clinical nutrition',
            'Preventive health services',
            'Exercise',
            'Obesity',
            'Dietary supplements',
        ],
        geo_subjects      => [ 'United States', 'Japan', 'Mediterranean Region' ],
        personal_subjects => [
            'Keys, Ancel, 1904-2004',
            'Pauling, Linus, 1901-1994',
            'Willett, Walter',
        ],
        corp_subjects => [
            'World Health Organization',
            'American Dietetic Association',
            'British Nutrition Foundation',
        ],
        form_genres => [ 'Textbooks', 'Clinical practice guidelines', 'Research reports' ],
        summaries   => [
            'A comprehensive introduction to nutrition science covering macronutrients, micronutrients, energy metabolism, dietary assessment, and the nutritional basis of major chronic diseases.',
            'Covers clinical nutrition assessment and support including malnutrition screening, enteral and parenteral nutrition, and the management of disease-related nutritional problems.',
            'An introduction to preventive medicine covering the determinants of health, screening, immunisation, and the prevention of chronic diseases at population level.',
            'A rigorous treatment of exercise physiology covering the metabolic, cardiovascular, and musculoskeletal responses to acute exercise and adaptations to training.',
            'Examines the biology, epidemiology, and treatment of obesity, covering energy balance, adipose tissue physiology, genetic factors, and lifestyle and pharmacological interventions.',
        ],
    },

    # === ARTS & CULTURE ===

    {
        name   => 'Music and Performing Arts',
        titles => [
            'Music Theory',
            'The History of Jazz',
            'Opera',
            'Ethnomusicology',
            'The Art of Choreography',
        ],
        subtitles => [
            'Harmony, Counterpoint, and Form',
            'From New Orleans to the Present',
            'A History',
            'Music, Culture, and Society',
            'Dance Composition and Creation',
        ],
        authors => [
            'Larsen, Jens P.',
            'Williams, Kwame L.',
            'Moretti, Francesca',
            'Nakashima, Emi',
            'Osei, Akosua',
        ],
        subjects => [
            'Music theory',
            'Jazz',
            'Opera',
            'Ethnomusicology',
            'Choreography',
            'Music--History and criticism',
        ],
        geo_subjects      => [ 'United States', 'Italy', 'Africa' ],
        personal_subjects => [
            'Bach, Johann Sebastian, 1685-1750',
            'Coltrane, John, 1926-1967',
            'Verdi, Giuseppe, 1813-1901',
        ],
        corp_subjects => [
            'Royal Opera House (London, England)',
            'Metropolitan Opera',
            'American Society of Composers, Authors and Publishers',
        ],
        form_genres => [ 'Textbooks', 'Biographies', 'Scores' ],
        summaries   => [
            'An introduction to music theory covering scales, intervals, chords, harmonic progression, counterpoint, musical form, and basic compositional techniques.',
            'A history of jazz from its origins in African American musical traditions through the major stylistic developments of the twentieth century to contemporary practice.',
            'Traces the development of opera from its origins in late sixteenth-century Florence through the works of Monteverdi, Mozart, Verdi, Wagner, and twentieth-century opera.',
            'An introduction to ethnomusicology covering fieldwork methods, transcription and analysis, music and identity, and the study of music in diverse cultural contexts.',
            'Examines the craft of choreography, covering movement analysis, compositional structures, the use of space and time, and collaboration in dance creation.',
        ],
    },

    {
        name   => 'Film, Media, and Cultural Studies',
        titles => [
            'Film Theory',
            'A History of Cinema',
            'Television and Society',
            'Cultural Theory',
            'Digital Media and Culture',
        ],
        subtitles => [
            'An Introduction',
            'The First Hundred Years',
            'Representation, Audiences, and Power',
            'Key Thinkers and Concepts',
            'Identity, Communities, and Platforms',
        ],
        authors => [
            'Andersson, Britta K.',
            'Moreau, Philippe',
            'Adichie, Tochukwu',
            'Matsumoto, Rie',
            "O'Sullivan, Niamh",
        ],
        subjects => [
            'Film criticism',
            'Motion pictures--History',
            'Television--Social aspects',
            'Culture--Study and teaching',
            'Digital media',
            'Popular culture',
        ],
        geo_subjects      => [ 'United States', 'France', 'India' ],
        personal_subjects => [
            'Godard, Jean-Luc',
            'Hitchcock, Alfred, 1899-1980',
            'Mulvey, Laura',
        ],
        corp_subjects => [
            'British Film Institute',
            'Academy of Motion Picture Arts and Sciences',
            'British Broadcasting Corporation',
        ],
        form_genres => [ 'Textbooks', 'Essays', 'Anthologies' ],
        summaries   => [
            'An introduction to film theory covering formalism, realism, auteur theory, apparatus theory, feminism, psychoanalysis, and postcolonial approaches to cinema.',
            'A survey of cinema history from the Lumière brothers to the digital era, covering major national cinemas, genres, studio systems, and technological change.',
            'Examines television as a social and cultural phenomenon, covering genre, representation, audience research, public service broadcasting, and the rise of streaming.',
            'Introduces cultural theory from Marx and Freud through the Frankfurt School, structuralism, poststructuralism, and postcolonial theory.',
            'Examines the cultural dimensions of digital media, covering social networks, platform economies, algorithmic culture, and the politics of digital identity.',
        ],
    },

    # === BUSINESS & MANAGEMENT ===

    {
        name   => 'Business, Finance, and Leadership',
        titles => [
            'Strategic Management',
            'Corporate Finance',
            'Marketing Management',
            'Organisational Behaviour',
            'Entrepreneurship',
        ],
        subtitles => [
            'Concepts and Cases',
            'Principles and Practice',
            'Analysis and Planning',
            'Leading and Managing Organisations',
            'Creating and Growing Ventures',
        ],
        authors => [
            'Thompson, Andrew R.',
            'Adeyemi, Bola',
            'Lindgren, Stig',
            'Nakamura, Koji',
            'Ferreira, Marta',
        ],
        subjects => [
            'Strategic planning',
            'Corporations--Finance',
            'Marketing',
            'Organizational behavior',
            'Entrepreneurship',
            'Leadership',
        ],
        geo_subjects      => [ 'United States', 'Great Britain', 'China' ],
        personal_subjects => [
            'Drucker, Peter F. (Peter Ferdinand), 1909-2005',
            'Porter, Michael E., 1947-',
            'Welch, Jack, 1935-2020',
        ],
        corp_subjects => [
            'Harvard Business School',
            'McKinsey and Company',
            'Fortune 500 companies',
        ],
        form_genres => [ 'Textbooks', 'Case studies', 'Handbooks, manuals, etc.' ],
        summaries   => [
            'A comprehensive text on strategic management covering competitive analysis, generic strategies, diversification, mergers and acquisitions, and the execution of strategy.',
            'An introduction to corporate finance covering capital budgeting, capital structure, dividend policy, risk and return, options, and corporate governance.',
            'Covers marketing strategy, market research, consumer behaviour, segmentation and targeting, the marketing mix, and digital marketing applications.',
            'Examines individual and group behaviour in organisations, covering motivation, leadership, communication, teams, organisational culture, and change management.',
            'An introduction to entrepreneurship covering opportunity recognition, business model design, venture financing, growth strategies, and the challenges of building new ventures.',
        ],
    },
);

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

my @PUB_YEARS  = ( 1997, 1999, 2002, 2004, 2006, 2008, 2010, 2012, 2014, 2016, 2018, 2020, 2022, 2023, 2024 );
my @PUBLISHERS = (
    'Academic Press', 'Cambridge University Press', 'Oxford University Press',
    'Springer',       'MIT Press',                  'Wiley',
    'Routledge',      'Elsevier',                   'McGraw-Hill',
    'Penguin Academic',
);
my @PUB_PLACES = ( 'London', 'New York', 'Cambridge', 'Oxford', 'Berlin', 'Chicago', 'Amsterdam' );

sub _pick {
    my ( $aref, $idx ) = @_;
    return $aref->[ $idx % scalar @{$aref} ];
}

# ---------------------------------------------------------------------------
# DELETE EXISTING BIBLIOS
# ---------------------------------------------------------------------------

sub delete_all_biblios {
    say "Deleting all existing biblio records...";
    my $biblios = Koha::Biblios->search;
    my $count   = 0;
    while ( my $biblio = $biblios->next ) {
        my $items = $biblio->items;
        while ( my $item = $items->next ) {
            $item->delete;
        }
        DelBiblio( $biblio->biblionumber );
        $count++;
        print '.'         if $count % 10 == 0;
        print " $count\n" if $count % 100 == 0;
    }
    say "\nDeleted $count record(s).";
}

# ---------------------------------------------------------------------------
# DELETE EXISTING AUTHORITIES
# ---------------------------------------------------------------------------

sub delete_all_authorities {
    say "Deleting all existing authority records...";
    my $auths = Koha::Authorities->search;
    my $count = 0;
    while ( my $auth = $auths->next ) {
        $auth->delete;
        $count++;
        print '.'         if $count % 10 == 0;
        print " $count\n" if $count % 100 == 0;
    }
    say "\nDeleted $count authority record(s).";
}

# ---------------------------------------------------------------------------
# AUTHORITY HELPERS
# ---------------------------------------------------------------------------

sub _ensure_authority {
    my ( $heading, $authtypecode, $variants ) = @_;
    $variants //= [];

    my $existing = Koha::Authorities->search( { heading => $heading } )->next;
    return $existing->authid if $existing;

    my $record = MARC::Record->new;
    $record->encoding('UTF-8');

    my ( $main_tag, $variant_tag, $ind1 );
    if ( $authtypecode eq 'TOPIC_TERM' ) {
        ( $main_tag, $variant_tag, $ind1 ) = ( '150', '450', ' ' );
    } elsif ( $authtypecode eq 'GEOGR_NAME' ) {
        ( $main_tag, $variant_tag, $ind1 ) = ( '151', '451', ' ' );
    } else {    # PERSO_NAME
        ( $main_tag, $variant_tag, $ind1 ) = ( '100', '400', '1' );
    }

    $record->append_fields( MARC::Field->new( $main_tag, $ind1, ' ', a => $heading ) );
    for my $variant (@$variants) {
        $record->append_fields( MARC::Field->new( $variant_tag, $ind1, ' ', a => $variant ) );
    }

    my $authid = AddAuthority( $record, undef, $authtypecode, { skip_record_index => 1 } );
    return $authid;
}

sub build_authority_index {
    say "Building authority records...";
    my %idx;
    my $count = 0;

    for my $topic (@TOPICS) {
        my $vf = $topic->{variant_forms} // {};

        for my $s ( @{ $topic->{subjects} } ) {
            my $key = "$s\tTOPIC_TERM";
            unless ( exists $idx{$key} ) {
                $idx{$key} = _ensure_authority( $s, 'TOPIC_TERM', $vf->{$s} // [] );
                $count++;
                print '.'         if $count % 10 == 0;
                print " $count\n" if $count % 100 == 0;
            }
        }
        for my $s ( @{ $topic->{geo_subjects} } ) {
            my $key = "$s\tGEOGR_NAME";
            unless ( exists $idx{$key} ) {
                $idx{$key} = _ensure_authority( $s, 'GEOGR_NAME', $vf->{$s} // [] );
                $count++;
                print '.'         if $count % 10 == 0;
                print " $count\n" if $count % 100 == 0;
            }
        }
        for my $s ( @{ $topic->{personal_subjects} } ) {
            my $key = "$s\tPERSO_NAME";
            unless ( exists $idx{$key} ) {
                $idx{$key} = _ensure_authority( $s, 'PERSO_NAME', $vf->{$s} // [] );
                $count++;
                print '.'         if $count % 10 == 0;
                print " $count\n" if $count % 100 == 0;
            }
        }
    }

    say "\nCreated/reused $count authority record(s).";
    return %idx;
}

# ---------------------------------------------------------------------------
# BUILD MARC RECORD
#
# Profiles (5 records each per topic):
#   A - Full:     title + subtitle + author + 3 x 650 + long 520
#   B - Geo:      title + subtitle + author + 2 x 650 + 651 + 655 + short 520
#   C - Personal: title + author + 2 x 650 + 600 + 520
#   D - Sparse:   title + author + 1 x 650  (no subtitle, no 520)
#   E - Corporate:title + subtitle + 1 x 650 + 651 + 610 + long 520  (no author)
# ---------------------------------------------------------------------------

sub make_marc_record {
    my ( $profile, $topic, $idx, $auth_index ) = @_;
    $auth_index //= {};

    my $record = MARC::Record->new;
    $record->encoding('UTF-8');

    my $title  = _pick( $topic->{titles},    $idx );
    my $sub    = _pick( $topic->{subtitles}, $idx );
    my $author = _pick( $topic->{authors},   $idx );
    my $year   = _pick( \@PUB_YEARS,         $idx );
    my $pub    = _pick( \@PUBLISHERS,        $idx );
    my $place  = _pick( \@PUB_PLACES,        $idx );

    # 100 — Personal author (all profiles except E)
    if ( $profile ne 'E' ) {
        $record->append_fields( MARC::Field->new( '100', '1', ' ', a => "$author," ) );
    }

    # 245 — Title / subtitle
    my $title_ind1 = ( $profile ne 'E' ) ? '1' : '0';
    if ( $profile eq 'A' || $profile eq 'B' || $profile eq 'E' ) {
        $record->append_fields(
            MARC::Field->new(
                '245', $title_ind1, '0',
                a => "$title :",
                b => "$sub /"
            )
        );
    } else {
        $record->append_fields( MARC::Field->new( '245', $title_ind1, '0', a => $title ) );
    }

    # 264 — Publication statement
    $record->append_fields(
        MARC::Field->new(
            '264', ' ', '1',
            a => "$place :",
            b => "$pub,",
            c => $year,
        )
    );

    # 300 — Physical description
    my $pages = 200 + ( $idx * 41 ) % 450;
    $record->append_fields( MARC::Field->new( '300', ' ', ' ', a => "$pages pages" ) );

    # 520 — Summary (all except D)
    if ( $profile ne 'D' ) {
        my $summary = _pick( $topic->{summaries}, $idx );
        $record->append_fields( MARC::Field->new( '520', ' ', ' ', a => $summary ) );
    }

    # 600 — Personal name subject (profile C only)
    if ( $profile eq 'C' ) {
        my $ps     = _pick( $topic->{personal_subjects}, $idx );
        my $authid = $auth_index->{"$ps\tPERSO_NAME"};
        $record->append_fields(
            MARC::Field->new(
                '600', '1', '0',
                a => $ps,
                ( $authid ? ( 9 => $authid ) : () ),
            )
        );
    }

    # 610 — Corporate name subject (profile E only)
    if ( $profile eq 'E' ) {
        my $cs = _pick( $topic->{corp_subjects}, $idx );
        $record->append_fields( MARC::Field->new( '610', '2', '0', a => $cs ) );
    }

    # 650 — Topical subject headings
    my $num_subs =
          ( $profile eq 'A' ) ? 3
        : ( $profile eq 'D' ) ? 1
        :                       2;
    for my $i ( 0 .. $num_subs - 1 ) {
        my $s      = _pick( $topic->{subjects}, $idx + $i );
        my $authid = $auth_index->{"$s\tTOPIC_TERM"};
        $record->append_fields(
            MARC::Field->new(
                '650', ' ', '0',
                a => $s,
                ( $authid ? ( 9 => $authid ) : () ),
            )
        );
    }

    # 651 — Geographic subject (profiles B and E)
    if ( $profile eq 'B' || $profile eq 'E' ) {
        my $gs     = _pick( $topic->{geo_subjects}, $idx );
        my $authid = $auth_index->{"$gs\tGEOGR_NAME"};
        $record->append_fields(
            MARC::Field->new(
                '651', ' ', '0',
                a => $gs,
                ( $authid ? ( 9 => $authid ) : () ),
            )
        );
    }

    # 655 — Form/genre (profile B only)
    if ( $profile eq 'B' ) {
        my $fg = _pick( $topic->{form_genres}, $idx );
        $record->append_fields( MARC::Field->new( '655', ' ', '7', a => $fg ) );
    }

    # 942 — Koha item type (required)
    $record->append_fields( MARC::Field->new( '942', ' ', ' ', c => 'BK' ) );

    return $record;
}

# ---------------------------------------------------------------------------
# ES REINDEX (standard search index only — not vector embeddings)
# ---------------------------------------------------------------------------

sub run_es_reindex {
    my $intranetdir = C4::Context->config('intranetdir');
    my $rebuild     = "$intranetdir/misc/search_tools/rebuild_elasticsearch.pl";
    unless ( -e $rebuild ) {
        warn "Could not find $rebuild — skipping Elasticsearch reindex\n";
        return;
    }
    say "Reindexing authorities (standard search index, not vector embeddings)...";
    my $exit = system( $^X, $rebuild, '-d', '-a', '-v' );
    warn "rebuild_elasticsearch.pl (authorities) exited with status $exit\n" if $exit;

    say "Reindexing biblios (standard search index, not vector embeddings)...";
    $exit = system( $^X, $rebuild, '-d', '-b', '-v' );
    warn "rebuild_elasticsearch.pl (biblios) exited with status $exit\n" if $exit;
}

# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

delete_all_authorities();
delete_all_biblios();

my %auth_index = build_authority_index();

say "Creating 1000 biblio records across 40 subject areas...";

my $total = 0;
for my $topic (@TOPICS) {
    for my $profile (qw( A B C D E )) {
        for my $idx ( 0 .. 4 ) {
            my $record = make_marc_record( $profile, $topic, $idx, \%auth_index );
            AddBiblio( $record, '', { skip_record_index => 1 } );
            $total++;
            print '.'         if $total % 10 == 0;
            print " $total\n" if $total % 100 == 0;
        }
    }
}

say "\nCreated $total biblio record(s).";
run_es_reindex();
say "Done.";
say "Note: run the embedding providers Re-index action to generate vector embeddings.";
