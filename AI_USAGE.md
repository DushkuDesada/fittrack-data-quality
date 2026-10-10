AI Usage

Tools

* Claude (Anthropic): Advanced SQL implementation and test automation assistance.
* pgAdmin 4: Independent SQL execution, data exploration, investigation, and validation.

Approach and Ownership

I approached this assignment by first building my own understanding of the data and business requirements.

I independently explored the database schema, analyzed table relationships, investigated data patterns, and executed initial SQL queries to establish a baseline understanding of the dataset and identify potential data-quality issues.

Once I understood the problem and expected behavior, I introduced AI to accelerate specific technical tasks rather than relying on it to define the approach.

AI-Assisted Implementation

I used Claude primarily for:

* Advanced SQL: Assisting with complex queries involving window functions, event pairing, deduplication, and time-zone handling.
* Test automation: Accelerating the implementation of the automated validation suite based on the identified data-quality requirements.

I retained responsibility for evaluating the generated logic, validating query results, and ensuring the implementation aligned with the business rules.

Quality Control and Critical Evaluation

I treated AI-generated output as a proposed implementation that required independent verification.

This included reviewing SQL logic, executing queries against the database, cross-checking results, and refining validation checks to account for edge cases.

One example was the investigation of duplicate device events. An initial interpretation suggested that records sharing the same source reference could represent separate visits. Further investigation of the event timestamps revealed a replay pattern affecting 3,036 records.

Based on this evidence, I applied deduplication using the earliest occurrence of each source reference to prevent inflated visit counts.

This reinforced the importance of validating assumptions against actual data rather than accepting plausible explanations.

Key Takeaway

My approach was to use AI as an implementation accelerator while retaining ownership of the problem analysis, business-rule interpretation, validation strategy, and final results.

AI helped reduce the time spent implementing technically complex SQL and automation logic, allowing me to focus more on investigating data quality, evaluating edge cases, and ensuring the reliability of the solution.