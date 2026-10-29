"""Writes assets/htr/subject_words.txt: study vocabulary the general word list
(SymSpell en-80k, first 50k entries) misses or ranks too low.

The recogniser's language layer only corrects towards words it knows, and an
unknown word is easily replaced by a frequent look-alike (Mariam's lowercase
"ocd" became "old"). This list makes the terms of her subjects (neuroscience,
psychology, biology and medicine, physics, chemistry, maths and statistics)
known words with the frequency of a rare but real word (about rank 15,000 of
the general list); a word that is already more frequent there keeps its own
count (the app keeps the larger one).

ACRONYMS are always written in capitals by the decoder
(`LineDecodeConfig.upperAcronyms` must list the same ones).

Usage: python docs/htr_bench/make_subject_words.py   (from the project root)
Words are written in lowercase, letters only; duplicates are dropped.
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, '..', '..', 'assets', 'htr', 'subject_words.txt'))

# Count of a subject word: about the 15,000th word of the general list.
COUNT = 1400000
# Count of an acronym: about the 9,000th word.
ACRONYM_COUNT = 3000000

NEUROSCIENCE = """
neuron neurons neuronal neural neuroscience neuroscientist neuroscientists
neurology neurological neurologist neuroanatomy neuroanatomical neurophysiology
neurophysiological neurochemistry neurochemical neurobiology neurobiological
neuropsychology neuropsychological neurotransmitter neurotransmitters
neurotransmission neuroplasticity neurogenesis neurodegeneration
neurodegenerative neurodevelopment neurodevelopmental neuroimaging neuroendocrine
neuromuscular neuropathy neuropathic neuroglia neurotoxin neurotoxic
neuropeptide neuropeptides neuromodulator neuromodulators neuromodulation
neurulation neuroscience neurosurgery neurosurgeon
axon axons axonal dendrite dendrites dendritic synapse synapses synaptic
presynaptic postsynaptic soma myelin myelinated myelination demyelination
unmyelinated glia glial astrocyte astrocytes oligodendrocyte oligodendrocytes
microglia schwann ependymal interneuron interneurons motoneuron motoneurons
cortex cortices cortical subcortical neocortex neocortical hippocampus hippocampal
amygdala thalamus thalamic hypothalamus hypothalamic cerebrum cerebral cerebellum
cerebellar brainstem medulla oblongata pons midbrain forebrain hindbrain
diencephalon telencephalon mesencephalon rhombencephalon prosencephalon
metencephalon myelencephalon limbic ganglia striatum striatal caudate putamen
pallidus globus accumbens substantia nigra frontal parietal temporal occipital
insula insular cingulate prefrontal precentral postcentral gyrus gyri sulcus
sulci fissure fissures callosum ventricle ventricles ventricular meninges
meningeal dura arachnoid cerebrospinal pituitary pineal hypophysis tegmentum
tectum colliculus colliculi fornix septum mammillary reticular
spinal vertebral vertebrae ganglion plexus afferent afferents efferent efferents
autonomic sympathetic parasympathetic somatic enteric peripheral
dopamine dopaminergic serotonin serotonergic acetylcholine cholinergic
acetylcholinesterase norepinephrine noradrenaline noradrenergic epinephrine
adrenaline adrenergic glutamate glutamatergic gabaergic glycine histamine
endorphin endorphins enkephalin enkephalins oxytocin vasopressin melatonin
cortisol agonist agonists antagonist antagonists reuptake receptor receptors
ionotropic metabotropic depolarization depolarisation hyperpolarization
hyperpolarisation repolarization repolarisation depolarize depolarized
hyperpolarized refractory saltatory excitatory inhibitory potentiation
exocytosis endocytosis vesicle vesicles cleft ranvier summation
reflex reflexes proprioception proprioceptive nociception nociceptor nociceptors
mechanoreceptor mechanoreceptors photoreceptor photoreceptors chemoreceptor
chemoreceptors thermoreceptor thermoreceptors retina retinal cochlea cochlear
vestibular olfactory gustatory auditory somatosensory homunculus plasticity
lateralization lateralisation hemisphere hemispheres hemispheric
aphasia apraxia agnosia ataxia amnesia anterograde retrograde dementia alzheimer
alzheimers parkinson parkinsons huntington huntingtons epilepsy epileptic
seizure seizures ischemia ischaemia ischemic hemorrhage haemorrhage concussion
encephalitis meningitis sclerosis neuralgia migraine migraines paralysis
paraplegia quadriplegia tetraplegia hemiplegia palsy dyslexia dyslexic
dyscalculia dyspraxia dysgraphia autism autistic tourette tourettes
schizophrenia schizophrenic psychosis psychotic bipolar mania manic depressive
anxiety phobia phobias insomnia narcolepsy apnea apnoea circadian
broca brocas wernicke wernickes gage
"""

PSYCHOLOGY = """
psychology psychologist psychologists psychological psychiatry psychiatric
psychiatrist psychotherapy psychotherapist psychopathology psychoanalysis
psychoanalytic psychodynamic psychometric psychosocial psychopharmacology
cognition cognitive metacognition behavior behaviour behaviors behaviours
behavioral behavioural behaviorism behaviourism behaviorist conditioning
conditioned unconditioned operant reinforcement reinforcer reinforcers
punishment stimulus stimuli extinction habituation sensitization sensitisation
perception perceptual attention attentional encoding retrieval consolidation
episodic semantic procedural declarative implicit explicit iconic echoic
mnemonic mnemonics schema schemas schemata heuristic heuristics
intelligence emotion emotional motivation personality introvert extrovert
introversion extroversion extraversion neuroticism conscientiousness
agreeableness unconscious subconscious consciousness superego
freud freudian piaget piagetian vygotsky pavlov pavlovian skinner maslow erikson
bandura milgram zimbardo kohlberg bowlby ainsworth chomsky
developmental attachment temperament adolescence adolescent adolescents infancy
diagnosis diagnoses diagnostic symptom symptoms syndrome syndromes disorder
disorders etiology aetiology prognosis prevalence comorbidity comorbid
treatment medication antidepressant antidepressants antipsychotic antipsychotics
anxiolytic anxiolytics placebo placebos hypothesis hypotheses
experimental correlational causation participant participants validity
reliability conformity obedience prejudice stereotype stereotypes
self esteem empathy altruism aggression resilience wellbeing mindfulness
"""

BIOLOGY = """
cell cells cellular membrane membranes nucleus nuclei cytoplasm cytoplasmic
organelle organelles mitochondria mitochondrion mitochondrial ribosome ribosomes
ribosomal endoplasmic reticulum golgi lysosome lysosomes cytoskeleton cytosol
vacuole vacuoles chloroplast chloroplasts protein proteins enzyme enzymes
enzymatic amino acids nucleotide nucleotides gene genes genetic genetics genome
genomes genomic genotype phenotype chromosome chromosomes chromosomal allele
alleles mutation mutations mitosis meiosis transcription replication
hormone hormones hormonal endocrine exocrine insulin glucagon glucose glycogen
metabolism metabolic homeostasis anatomy anatomical physiology physiological
tissue tissues organ organs muscle muscles muscular skeletal cardiac tendon
tendons ligament ligaments cartilage artery arteries arterial vein veins venous
capillary capillaries plasma hemoglobin haemoglobin erythrocyte erythrocytes
leukocyte leukocytes platelet platelets lymph lymphatic lymphocyte lymphocytes
renal hepatic pulmonary respiratory digestive gastrointestinal intestine
intestines intestinal pancreas pancreatic thyroid adrenal gland glands
antibody antibodies antigen antigens pathogen pathogens immune immunity
immunology inflammation inflammatory infection bacteria bacterial virus viral
fungi fungal microbe microbes microbial microbiology biochemistry biochemical
photosynthesis respiration aerobic anaerobic osmosis diffusion homeostatic
evolution evolutionary natural selection adaptation species ecosystem
ecosystems ecology organism organisms embryo embryonic fetus foetus fetal
zygote gamete gametes ovary ovaries testes sperm oocyte fertilization
fertilisation pathology pathological physiology epidemiology pharmacology
pharmacological dosage diuretic analgesic anesthesia anaesthesia anesthetic
"""

PHYSICS = """
pascal pascals newton newtons joule joules watt watts volt volts ampere amperes
ohm ohms coulomb coulombs hertz kelvin celsius fahrenheit
pressure gauge atmospheric hydrostatic hydraulic barometer barometric manometer
buoyancy buoyant archimedes bernoulli viscosity viscous density densities
velocity velocities acceleration momentum friction gravitational inertia
kinetic potential torque equilibrium displacement vector vectors scalar scalars
oscillation oscillations frequency frequencies wavelength wavelengths amplitude
electromagnetic photon photons electron electrons proton protons neutron
neutrons nucleon isotope isotopes thermodynamics thermodynamic entropy enthalpy
conduction convection capacitance capacitor capacitors resistor resistors
inductor inductance magnetism refraction diffraction interference polarization
quantum relativity radioactivity radioactive decay fission fusion
kilogram kilograms kilometre kilometres kilometer kilometers millimetre
millimetres centimetre centimetres newtonian
"""

CHEMISTRY = """
ionic covalent electronegativity isotope compound compounds molecule molecules
molecular atom atoms atomic oxidation reduction redox catalyst catalysts
catalysis reactant reactants solvent solute solutes solubility concentration
concentrations molarity molar molality titration buffer buffers alkaline
alkali hydroxide hydrogen oxygen nitrogen carbon sodium potassium chloride
calcium magnesium phosphate phosphorus sulfur sulphur organic inorganic
hydrocarbon hydrocarbons polymer polymers monomer monomers lipid lipids
carbohydrate carbohydrates cholesterol triglyceride triglycerides
"""

MATHS = """
mean median variance deviation regression probability probabilities
distribution distributions statistics statistical significance significant
hypothesis correlation coefficient coefficients covariance quartile quartiles
percentile percentiles histogram scatterplot skewness kurtosis anova
parametric nonparametric chi binomial poisson gaussian logarithm logarithms
logarithmic exponential derivative derivatives integral integrals equation
equations quadratic polynomial matrix matrices algebra calculus geometry
trigonometry sine cosine tangent
"""

GENERAL = """
lecture lectures tutorial tutorials seminar seminars assignment assignments
coursework syllabus semester midterm midterms exam exams revision definition
definitions summary diagram diagrams example examples
"""

# The app's people (it is "Mariam's Notes"): the general list lacks their
# names, and the owner's "Mariam" came out as "Marianne" (v1.8.0).
NAMES = """
mariam malek baghdadi
"""

ACRONYMS = """
adhd ocd ptsd gaba dna rna mrna trna atp adp eeg ecg ekg emg mri fmri cns pns
iq ssri ssris snri maoi dsm icd bmi hiv copd cpr icu bpm acth tsh lsd mdma
nmda ampa ltp ltd
"""


# v1.11.0: terms of her courses autocorrect took for misspellings (the
# British spellings come through the -ise/-ize rule in text_polish.dart).
MORE_NEURO_PSYCH = """
interoception interoceptive proprioception proprioceptive nociception nociceptor nociceptors
synaptically myelinated myelination demyelination demyelinating unmyelinated
depolarizing repolarizing hyperpolarization hyperpolarized hyperpolarizing depolarized repolarized
excitability neuromodulator neuromodulators neuromodulation neurotransmission glutamate glutamatergic gabaergic
dendrites dendritic somas soma ganglia ganglion thalamic hypothalamic cortical subcortical neocortex neocortical
limbic hippocampal amygdala amygdalae amygdalar cerebellar prefrontal orbitofrontal dorsolateral ventromedial
mesolimbic mesocortical nigrostriatal tuberoinfundibular dopaminergic serotonergic cholinergic noradrenergic adrenergic
interneuron interneurons internode internodes neurone neurones axonal axons nodal ranvier schwann oligodendrocyte
oligodendrocytes astrocyte astrocytes microglia microglial ependymal saltatory reconsolidation consolidation
centration egocentrism decentration conservation operant reinforcer reinforcers punisher punishers habituated habituation
sensitization sensitisation dishabituation priming mnemonic mnemonics heuristic heuristics schema schemas schemata
avoidant ambivalent neurodevelopmental neurodivergent neurotypical comorbid comorbidity etiology aetiology
symptomatology psychopathology psychoanalytic psychodynamic behaviourist behaviorist behaviourism behaviorism
cognitivist humanistic eudaimonia hedonic introversion extraversion extroversion conscientiousness agreeableness neuroticism
obsessive compulsions phobias phobic psychotic delusional hallucinations schizoid metacognition neurogenesis
neuroplasticity plasticity potentiation postsynaptic presynaptic ionotropic metabotropic reuptake agonist agonists
antagonist antagonists anxiolytic anxiolytics antipsychotic antipsychotics antidepressant antidepressants
benzodiazepine benzodiazepines endorphins oxytocin cortisol melatonin norepinephrine noradrenaline adrenaline epinephrine
somatosensory striatum accumbens nigra substantia meninges arachnoid gyrus gyri sulcus sulci insula cingulate fornix
mammillary pituitary pineal tectum tegmentum colliculus colliculi cerebrospinal
"""


def words(block):
    return [w for w in re.split(r'\s+', block.strip().lower()) if w]


def main():
    seen = set()
    lines = [
        '# Study vocabulary for the handwriting recogniser, written for NeatInk.',
        '# Generated by docs/htr_bench/make_subject_words.py: edit the script, not this file.',
        '# Format: word count (lines that do not parse, like these, are skipped).',
    ]
    for title, block, count in [
        ('neuroscience', NEUROSCIENCE, COUNT),
        ('psychology', PSYCHOLOGY, COUNT),
        ('biology and medicine', BIOLOGY, COUNT),
        ('physics', PHYSICS, COUNT),
        ('chemistry', CHEMISTRY, COUNT),
        ('maths and statistics', MATHS, COUNT),
        ('general study words', GENERAL, COUNT),
        ('more neuroscience and psychology', MORE_NEURO_PSYCH, COUNT),
        ('acronyms', ACRONYMS, ACRONYM_COUNT),
        ('names', NAMES, COUNT),
    ]:
        lines.append(f'# {title}')
        for w in words(block):
            if not re.fullmatch(r'[a-z]+', w) or w in seen:
                continue
            seen.add(w)
            lines.append(f'{w} {count}')
    with open(OUT, 'w', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'{len(seen)} words -> {OUT}')


if __name__ == '__main__':
    main()
