# CSCI 4623 — Digital Forensics / Spring 2026
## Lab Homework 1

* **Exhibit:** `exhibit-a.dd`  
* **Deliverable:** Written forensic report (see Submission below)  
* **Submission:** via `gitlab.cs.uno.edu`
* **Due:** `Apr 1 @11:59pm`
---

## Scenario

A USB drive (Exhibit A) has been seized from a departing employee suspected of exfiltrating proprietary data. During the in-class lab you examined its NTFS surface and documented a number of anomalies. The investigation is not finished and your task is to complete it.

---

## The Assignment

The lab established what is visible at the filesystem layer. Your job is to determine what lies beneath it, recover whatever can be recovered, and produce a report that tells the full story of this drive.

You are not given a procedure. You are expected to use the tools and techniques from the course, and your own judgment, to decide what to examine, in what order, and how to interpret what you find.

Some questions to guide your thinking, not your steps:

- The partition table accounts for part of this disk. What about the rest?
- You found a string in the pre-partition slack during the lab. Is it significant on its own, or does its significance depend on something else on the drive?
- The NTFS surface looked relatively clean. Does that mean it was clean?

---

## Report Requirements

Your report has two required structural elements. Everything else is yours to organize.

**Executive summary.** Lead with a one-page summary written for a non-technical supervising investigator. No tool names, no byte offsets: state what the exhibit is, what you found, and what it means in plain language. A reader who gets no further than this page should understand the substance of the investigation.

**Technical body.** Document your examination of the exhibit in whatever depth and structure the evidence warrants. You decide what to examine, in what order, and how to present it. A competent forensic examiner reading your report should be able to verify every claim you make and reproduce every result you report.

The technical body must not be a checklist, but a standard: account for the whole disk, not just the filesystem; ground every conclusion in specific evidence; and leave the reader with a clear picture of what this drive was used for.

---

## On the Approach

You will need to work below the filesystem layer. The tools and concepts relevant to this assignment have been covered in lecture and lab. If you find yourself uncertain about what to examine next, the evidence on the drive will suggest directions.

All commands you run must appear in an appendix with enough context that someone else could reproduce your work from scratch using your report alone.

---

## Grading

Reports are graded on four dimensions, each accounting for 25% of your score:

* **Coverage** — Did you find what is there to be found? Did you account for the whole disk?
* **Accuracy** — Are your technical findings correct? Are hashes, offsets, and file contents reported accurately?
* **Reasoning** — Do your conclusions follow from the evidence? Are claims bounded to what the artifacts actually support?
* **Communication** — Is the report coherent? Would the executive summary make sense to someone with no forensics background?

There are no points for following a particular procedure. There are points for finding things, correctly characterizing them, and explaining what they mean.

---

## Submission
**Remember that this work is part of your preparation to be a software engineering professional -- every requirement counts and it will be counted!** 

- *You must strictly follow the requirements of this section to the letter.* 
- Your submission will be downloaded automatically from your code repo. Failure counts against you.

### Creating a working/submission repo

You are provided a structured reference repo. 
Sign on to [gitlab.cs.uno.edu](https://gitlab.cs.uno.edu) using your UNO credentials and go to 
[https://gitlab.cs.uno.edu/vroussev/4623s26-lab1](https://gitlab.cs.uno.edu/vroussev/4623s26-lab1).
Fork the repository into your namespace `<yourlogin>` and **retain the `4623s26-lab1`** slug. 

This repo (`https://gitlab.cs.uno.edu/<your_login>/4623s26-lab1`) will be used to pull your final submission. 
Whatever report and supporting evidence you intend to submit, must be *git pushed* to this repo before the deadline. 

**Your repository is the ONLY acceptable submission mechanism -- no email, *Canvas*, etc.**

- Once you have the fork, you can *git clone* the repo to `cyber-range.cs.uno.edu`, or wherever you choose to work on the assignment.
- Your report must be named `4623s26-lab1-report--<your_login>.md` and must be written in standard markdown.
- Place any files/data extracted from the in `/evidence` and any tool output in `/logs`.
- Every file you place in these two folders **must** have relevance to the case and **must** be referenced in the report.
- Do not commit temporary / cached / backup / version and other junk files to the repo. You *will* lose points.
