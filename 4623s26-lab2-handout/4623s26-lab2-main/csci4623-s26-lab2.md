# CSCI 4623 — Digital Forensics / Spring 2026
## Lab Homeworks 2 and 3

- **Image:** `csci4623-s26-lab2.dd`
- **SHA-256:** `d5721ca739f2a24fa6b33979148fe9290724d8a5dfddd1d02fafd1f6dfce8e5a`
- **Deliverable:** Written forensic report
- **Submission:** via `gitlab.cs.uno.edu`  
- **Due:** 
  - Q1-Q3 ` Apr 30 @11:59pm`
  - Q4-Q5 `  May 4 @11:59pm`

---

## Scenario

You have just been hired and your first assignment is to examine a USB drive image sent by someone who calls himself `w4ld0` and claims to know of long-existant critical vulnerabilities in the company's infrastructure that, if released, would cause potentially severe damage to the business.

Management suspects that this *may* be from a recently-departed employee who did not leave on the best of terms. In any case, `w4ld0` has apparently taken note of your hiring and is giving you a chance to earn his respect by solving a puzzle. If you do, you get a private disclosure and 90 days to fix things. Otherwise, he goes public and your sleep prognosis for the next month looks pretty bleak.

### Conventions

You **must** follow the following conventions:

- **hashes**: sha256
- **addresses** , **offsets**: hexadecimal 
- **length**: in bytes, hexadecimal

In all cases, narratively explain your forensic reasoning, provide supporting evidence and express your level of certainty based on the evidence. Insufficiently explained results yield little/no credit.

## The `w4ld0` Challenge

### >> Split Personality

*1. How many partitions/volumes are discernable on the image? For each claimed one, you must provide the following:*

- starting address and length
- sha256 hash
- filesystem type
- volume label (if any)
- accesssibility: what tools and knowledge are required to access the content (be specific) 
- state:
  - mountable as is (standard fs tools pick it up automatically)
  - intact (mountable but requires additional commands / parameters)
  - modified (mountable but has integrity errors and/or shows signs of manipulation)
  - recoverable (some/all files are there but require recovery)
  - detectable (there are identifiable traces but low-level file reconstruction is necessary)
- if the state is less than intact, explain 

### >> Undercurrents

*2. Start with the obvious and look underneath it.*

- Find all the Waldos. Explain location, recovery process, provide hash
- Find the special one who shall be king soon. Explain location, recovery process, provide hash

### >> Pompeii FS

*Like Pompeii beneath the ash,    
CVEs got lost in a flash.  
Carve through blocks, parse through nodes,   
Bring us back what here belongs.*

*3. The volcanic ashes from Mount Vesuvius' 79AD eruption covered and preserved much of Pompeii -- did something similar happen to a filesystem that was on this image? If so:*

- Describe what happened. Was is it the result of normal operations, or was manipulation involved?
- What is left behind and how can it be recovered?
- Write a shell script that this automatically.
- Provide starting address, hash and any other info you may have about each file recovered.

---

### >> `Waldo7`

*4. Find `Waldo7` -- provide volume, starting address and file hash as proof*

- How was it placed on the volume and were any steps taken to conceal it? If so, how could it be detected with existing system administration tools.
- How many effectively identical "siblings" does it have? Provide name, starting address, hash for each one.


### >> The Snake Pit

*5. Find the nested ones and recover them:*

- Provide starting addresses and hashes for each recovered one.
- How did they become nested -- was it a natural occurence, or was it the result of manipulation? 
- Provide a script that performs the recovery automatically -- you can shell-script together existing tools, or build a custom one for this case.

---

## Report Requirements

Your report has two required structural elements. Everything else is yours to organize.

**Executive summary.** Lead with a one-page summary written for a non-technical supervising investigator. No tool names, no byte offsets: state what the exhibit is, what you found, and what it means in plain language. A reader who gets no further than this page should understand the substance of the investigation.

**Technical body.** Document your examination of the exhibit in whatever depth and structure the evidence warrants. You decide what to examine, in what order, and how to present it. A competent forensic examiner reading your report should be able to verify every claim you make and reproduce every result you report.

The technical body must not be a checklist, but a standard: account for the whole disk, not just the filesystem; ground every conclusion in specific evidence; and leave the reader with a clear picture of what this drive was used for.

## Technical Approach

You will need to work both at and below the filesystem layer. The tools and concepts relevant to this assignment have been covered in lecture and lab. If you find yourself uncertain about what to examine next, the evidence on the drive will suggest directions.

All commands you run must appear in an appendix with enough context that someone else could reproduce your work from scratch using your report alone.


## Grading

Reports are graded on four dimensions, each accounting for 25% of your score:

- **Coverage**— Did you find what is there to be found? Did you account for the whole disk?
- **Accuracy**— Are your technical findings correct? Are hashes, offsets, and file contents reported accurately?
- **Reasoning**— Do your conclusions follow from the evidence? Are claims bounded to what the artifacts actually support?
- **Communication**— Is the report coherent? Would the executive summary make sense to someone with no forensics background?

There are no points for following a particular procedure. There are points for finding things, correctly characterizing them, and explaining what they mean.

---

## Submission
**Remember that this work is part of your preparation to be a software engineering professional -- every requirement counts and it will be counted!**

- *You must strictly follow the requirements of this section to the letter.* 
- Your submission will be downloaded automatically from your code repo. Failure counts against you.

### Creating a working/submission repo

You are provided a structured reference repo.  
Sign on to [gitlab.cs.uno.edu](https://gitlab.cs.uno.edu) using your UNO credentials and go to 
[https://gitlab.cs.uno.edu/vroussev/4623s26-lab2](https://gitlab.cs.uno.edu/vroussev/4623s26-lab2).  
Fork the repository into your namespace `<yourlogin>` and **retain** the `4623s26-lab2` slug. 

This repo (`https://gitlab.cs.uno.edu/<your_login>/4623s26-lab2`) will be used to pull your final submission. 
Whatever report and supporting evidence you intend to submit, must be *git pushed* to this repo before the deadline. 

**Your repository is the ONLY acceptable submission mechanism -- no email, *Canvas*, etc.**

- Once you have the fork, you can *git clone* the repo to `cyber-range.cs.uno.edu`, or wherever you choose to work on the assignment.
- Your report must be named `4623s26-lab2-report--<your_login>.md` and must be written in standard markdown.
- Place any files/data extracted from the the image in the `/evidence` folder; 
  code/scripts in `./code`; tool output in `/logs`.
- For Q1-Q3 submission, use commit message `"Lab 2 Q1-Q3 Submission"` (case and space sensitive).
- For Q4-Q5 submission, use commit message `"Lab 3 Q4-Q5 Submission"` (same).
- Every file you place in these folders **must** have relevance to the case and **must** be referenced in the report.
- Do not commit temporary / cached / backup / version and other junk files to the repo. You *will* lose points.
