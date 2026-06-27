# GSAF INTELLECTUAL PROPERTY LICENSE AGREEMENT

**Effective Date:** _______________

**License Agreement No.:** GSAF-LIC-______

**Between:**

**Verily** ("Licensor")
A technology company developing cryptographic hardware IP
Address: _______________

**AND**

**_______________** ("Licensee")
Address: _______________

---

## 1. DEFINITIONS

**"GSAF IP"** means the GreenField Secure Arithmetic Fabric, including:
- RTL source code (SystemVerilog) for the cryptographic fabric chassis
- Cryptographic engine modules (ModExp, ModInv, PQC, RSA-CRT, ECC)
- Golden models (Python algorithmic specifications)
- Verification artifacts (testbenches, formal properties, evidence packs)
- CLI tooling (GSAF Studio)
- Documentation (architecture, verification, integration guides)

**"Licensed Product"** means the specific semiconductor device or ASIC designed by Licensee that incorporates the GSAF IP.

**"Documentation"** means the technical documentation, integration guides, and verification evidence delivered with the GSAF IP.

**"Net Sales Price"** means the gross invoiced amount for the Licensed Product, less applicable taxes, returns, and allowances.

## 2. GRANT OF LICENSE

### 2.1 License Grant
Subject to the terms and conditions of this Agreement, Licensor grants Licensee a non-exclusive, non-transferable license to:

(a) **Use** the GSAF IP for the sole purpose of designing, simulating, and manufacturing the Licensed Product;

(b) **Integrate** the GSAF IP into the Licensed Product;

(c) **Reproduce** the GSAF IP as part of the Licensed Product for manufacturing;

(d) **Use** the Documentation for internal purposes related to the above activities.

### 2.2 Restrictions
Licensee shall NOT:

(a) Sublicense, sell, or distribute the GSAF IP as a standalone product or IP core;

(b) Reverse engineer, decompile, or disassemble the GSAF IP beyond what is necessary for integration;

(c) Remove or alter any proprietary notices, copyright notices, or trademarks;

(d) Use the GSAF IP to provide cryptographic services to third parties (e.g., as a cloud HSM);

(e) Use the GSAF IP in any application requiring Common Criteria or FIPS 140-3 certification without prior written approval from Licensor.

## 3. LICENSE FEES AND ROYALTIES

### 3.1 Upfront License Fee
Licensee shall pay Licensor a one-time license fee of **$_______________** ("License Fee") payable within thirty (30) days of the Effective Date.

### 3.2 Per-Unit Royalty
For each Licensed Product manufactured or sold, Licensee shall pay Licensor a royalty of **_____%** of Net Sales Price, payable quarterly within thirty (30) days after the end of each calendar quarter.

### 3.3 Minimum Annual Royalty
Beginning in the second year of this Agreement, Licensee shall pay a minimum annual royalty of **$_______________**, regardless of actual sales. Minimum royalties are creditable against actual royalties owed.

### 3.4 Evidence Pack Add-On
The following optional add-ons are available for separate purchase:

| Add-On | Description | Price |
|--------|-------------|-------|
| Certification Pack | FIPS 140-3 CAVP evidence, CC documentation | $_______________ |
| TVLA Report | Side-channel leakage assessment on FPGA | $_______________ |
| PPA Datasheet | Post-synthesis results for specific nodes | $_______________ |
| Custom Engine NRE | Development of custom crypto engine | $_______________ |

## 4. DELIVERY

### 4.1 Initial Delivery
Upon execution and payment of the License Fee, Licensor shall deliver:

(a) GSAF IP RTL source code (encrypted archive)

(b) Golden models and verification testbenches

(c) Evidence pack (tier as purchased)

(d) Integration documentation

(e) License key for the GSAF Studio CLI

### 4.2 Delivery Format
All deliverables shall be provided electronically via secure file transfer. Source code shall be delivered in encrypted form with decryption key provided separately.

## 5. SUPPORT AND MAINTENANCE

### 5.1 Initial Support
Licensor shall provide technical support for **twelve (12) months** from the Effective Date, including:

(a) Email support during business hours (response within 2 business days)

(b) Bug fixes for the GSAF IP as delivered

(c) Integration assistance (up to 40 hours)

### 5.2 Maintenance Updates
After the initial support period, Licensee may purchase annual maintenance at **_____%** of the original License Fee per year, which includes:

(a) Bug fixes and minor updates

(b) New golden model releases

(c) Updated evidence packs

### 5.3 Support Exclusions
Support does not include:

(a) Custom modifications to the GSAF IP

(b) Integration with Licensee's proprietary systems

(c) Certification lab engagement or testing

## 6. INTELLECTUAL PROPERTY RIGHTS

### 6.1 Ownership
The GSAF IP and all intellectual property rights therein are and shall remain the exclusive property of Licensor. This Agreement does not transfer any ownership rights.

### 6.2 Improvements
Any improvements, modifications, or derivative works of the GSAF IP created by Licensee shall be owned by Licensee, provided that Licensor retains all rights to the underlying GSAF IP.

### 6.3 No Implied Licenses
Except as expressly granted herein, no other licenses are implied under any patents, copyrights, or other intellectual property rights.

## 7. CONFIDENTIALITY

### 7.1 Confidential Information
The GSAF IP, Documentation, and all technical information exchanged under this Agreement are Confidential Information governed by the Mutual Non-Disclosure Agreement between the Parties dated _______________ (the "NDA").

### 7.2 Source Code Escrow
If requested by Licensee, Licensor may place the GSAF IP source code in escrow with a mutually agreed escrow agent, subject to customary escrow terms and conditions.

## 8. WARRANTIES AND DISCLAIMERS

### 8.1 Warranty
Licensor warrants that:

(a) It has the right to grant the licenses set forth in this Agreement;

(b) To its knowledge, the GSAF IP does not infringe any third-party intellectual property rights;

(c) The GSAF IP will perform substantially in accordance with the Documentation for a period of twelve (12) months from delivery.

### 8.2 Disclaimer
EXCEPT AS EXPRESSLY SET FORTH IN SECTION 8.1, THE GSAF IP IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.

### 8.3 No Certification Warranty
Licensor makes no warranty regarding the outcome of any certification process (FIPS, Common Criteria, etc.) using the GSAF IP. Licensee is solely responsible for obtaining any required certifications.

## 9. LIMITATION OF LIABILITY

IN NO EVENT SHALL LICENSOR BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING LOSS OF PROFITS, DATA, OR BUSINESS OPPORTUNITIES, ARISING OUT OF THIS AGREEMENT, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

LICENSOR'S TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT OF LICENSE FEES PAID BY LICENSEE UNDER THIS AGREEMENT.

## 10. TERM AND TERMINATION

### 10.1 Term
This Agreement shall commence on the Effective Date and continue for **five (5) years**, unless earlier terminated in accordance with this Section.

### 10.2 Termination for Cause
Either Party may terminate this Agreement upon thirty (30) days' written notice if the other Party:

(a) Materially breaches any provision and fails to cure within such period;

(b) Becomes insolvent, files for bankruptcy, or makes an assignment for the benefit of creditors.

### 10.3 Effects of Termination
Upon termination:

(a) All licenses granted hereunder shall immediately terminate;

(b) Licensee shall cease all use of the GSAF IP within sixty (60) days;

(c) Licensee may sell existing inventory of Licensed Products containing the GSAF IP for up to twelve (12) months after termination;

(d) All outstanding royalties and fees shall become immediately due and payable.

## 11. INDEMNIFICATION

### 11.1 Licensor Indemnity
Licensor shall defend, indemnify, and hold harmless Licensee against any claim that the GSAF IP infringes a valid patent, copyright, or trade secret of a third party, subject to the limitations in Section 9.

### 11.2 Licensee Indemnity
Licensee shall defend, indemnify, and hold harmless Licensor against any claim arising from Licensee's use of the GSAF IP in combination with other products or in a manner not authorized by this Agreement.

## 12. EXPORT COMPLIANCE

Licensee shall comply with all applicable export control laws and regulations in connection with the GSAF IP and Licensed Products.

## 13. GOVERNING LAW AND DISPUTE RESOLUTION

### 13.1 Governing Law
This Agreement shall be governed by the laws of _______________, without regard to conflict of laws principles.

### 13.2 Dispute Resolution
Any dispute arising out of this Agreement shall be resolved through binding arbitration under the rules of _______________. The arbitration shall be conducted in _______________.

## 14. GENERAL PROVISIONS

### 14.1 Assignment
Neither Party may assign this Agreement without the prior written consent of the other Party, except in connection with a merger, acquisition, or sale of substantially all assets.

### 14.2 Notices
All notices shall be in writing and delivered to the addresses set forth above or to such other address as either Party may designate.

### 14.3 Entire Agreement
This Agreement, together with the NDA, constitutes the entire agreement between the Parties with respect to the subject matter hereof.

### 14.4 Amendments
This Agreement may be amended only by written instrument signed by both Parties.

### 14.5 Severability
If any provision is held invalid or unenforceable, the remaining provisions shall continue in full force and effect.

---

**IN WITNESS WHEREOF**, the Parties have executed this Agreement as of the Effective Date.

**Verily (Licensor)**

Signature: _______________

Name: _______________

Title: _______________

Date: _______________

**Licensee**

Signature: _______________

Name: _______________

Title: _______________

Date: _______________
