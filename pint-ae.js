/*
 * PINT-AE (UAE e-invoicing) UBL 2.1 XML builder.
 *
 * This generates a structurally compliant PINT AE v1.0.2 invoice/credit-note
 * document (urn:peppol:pint:billing-1@ae-1) covering the mandatory + UAE-
 * specific (BTAE) fields for a standard domestic tax invoice or tax credit
 * note. It does NOT transmit anything to the FTA — under the UAE's 5-corner
 * model, only a Ministry-accredited Service Provider (ASP) may validate and
 * send e-invoices. This module only produces the XML payload that would be
 * handed to an ASP's API once the store has contracted one.
 *
 * Reference: UAE MoF Electronic Invoicing Guidelines, PINT AE Data
 * Dictionary (PINT v1.0.2). Field codes (IBT-xxx / BTAE-xx) are noted inline.
 */

function pintAeXmlEscape(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function pintAeNum(n, decimals) {
  return Number(n || 0).toFixed(decimals == null ? 2 : decimals);
}

function pintAeUuid() {
  if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
  // Fallback UUID v4 for older browsers.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0, v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/**
 * Build a PINT-AE compliant XML string for one invoice.
 *
 * @param {object} params
 * @param {object} params.store   - row from `stores` (needs legal_name/name,
 *   tax_number, license_number/commercial_registration_number,
 *   legal_registration_id_type, address, country='AE', emirate_code,
 *   peppol_endpoint_id, vat_rate)
 * @param {object} params.invoice - row from `invoices` (needs invoice_number,
 *   created_at, type ('sale'|'return'|...), total_amount, vat_amount,
 *   gold_value, fabrication_fees, related_invoice_number [resolved by caller])
 * @param {object|null} params.customer - row from `customers` (name/legal_name,
 *   tax_number, address, is_company) or null for a walk-in/individual buyer
 * @param {Array} params.items   - invoice_items rows (needs description,
 *   karat, weight_grams, accounting_weight_grams, line_total)
 * @returns {string} XML document text
 */
function buildPintAeXml(params) {
  const store = params.store || {};
  const invoice = params.invoice || {};
  const customer = params.customer || null;
  const items = params.items || [];

  const isCreditNote = invoice.type === 'return';
  const invoiceTypeCode = isCreditNote ? '381' : '380'; // IBT-003
  const uuid = pintAeUuid(); // BTAE-07
  const issueDate = (invoice.created_at ? new Date(invoice.created_at) : new Date()).toISOString().slice(0, 10); // IBT-002
  const vatRate = Number(store.vat_rate != null ? store.vat_rate : 5);
  const vatCategoryCode = vatRate > 0 ? 'S' : 'Z'; // IBT-118 (Standard / Zero-rated)

  const sellerLegalName = store.legal_name || store.name || ''; // IBT-027
  const sellerRegId = store.license_number || store.commercial_registration_number || ''; // IBT-030
  const sellerRegIdType = store.legal_registration_id_type || 'TL'; // BTAE-15
  const sellerTrn = store.tax_number || ''; // IBT-031
  const sellerEndpoint = store.peppol_endpoint_id || ''; // IBT-034 — blank until an ASP assigns one
  const sellerCountry = store.country === 'United Arab Emirates' || !store.country ? 'AE' : store.country; // IBT-040

  const buyerName = customer ? (customer.legal_name || customer.name || 'Cash Customer') : 'Cash Customer'; // IBT-044
  const buyerTrn = customer && customer.is_company ? (customer.tax_number || '') : ''; // IBT-048
  const buyerAddress = customer ? (customer.address || '') : ''; // IBT-050

  // Invoice lines (IBT-126 group). Gold-bearing lines are quantified in
  // grams (unit GRM); non-weighted lines (e.g. a diamond-only item) fall
  // back to a single "each" (C62) unit.
  let sumLineNet = 0;
  const lineXml = items.map(function (it, idx) {
    const lineId = idx + 1; // IBT-126
    const weight = Number(it.accounting_weight_grams != null ? it.accounting_weight_grams : it.weight_grams) || 0;
    const lineTotal = Number(it.line_total) || 0;
    const lineNet = lineTotal / (1 + vatRate / 100); // VAT-exclusive net amount for this line
    sumLineNet += lineNet;
    const hasWeight = weight > 0;
    const qty = hasWeight ? weight : 1;
    const unitCode = hasWeight ? 'GRM' : 'C62';
    const unitPrice = lineNet / qty;
    const itemName = it.description || (it.karat ? ('Gold item ' + it.karat + 'K') : 'Item');
    return (
      '  <cac:InvoiceLine>\n' +
      '    <cbc:ID>' + lineId + '</cbc:ID>\n' +
      '    <cbc:InvoicedQuantity unitCode="' + unitCode + '">' + pintAeNum(qty, hasWeight ? 3 : 0) + '</cbc:InvoicedQuantity>\n' +
      '    <cbc:LineExtensionAmount currencyID="AED">' + pintAeNum(lineNet) + '</cbc:LineExtensionAmount>\n' +
      '    <cac:Item>\n' +
      '      <cbc:Name>' + pintAeXmlEscape(itemName) + '</cbc:Name>\n' +
      '      <cac:ClassifiedTaxCategory>\n' +
      '        <cbc:ID>' + vatCategoryCode + '</cbc:ID>\n' +
      (vatRate > 0 ? '        <cbc:Percent>' + pintAeNum(vatRate) + '</cbc:Percent>\n' : '') +
      '        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>\n' +
      '      </cac:ClassifiedTaxCategory>\n' +
      '    </cac:Item>\n' +
      '    <cac:Price>\n' +
      '      <cbc:PriceAmount currencyID="AED">' + pintAeNum(unitPrice, hasWeight ? 4 : 2) + '</cbc:PriceAmount>\n' +
      '    </cac:Price>\n' +
      '  </cac:InvoiceLine>'
    );
  }).join('\n');

  const totalWithVat = Number(invoice.total_amount) || 0; // IBT-112
  const totalVat = Number(invoice.vat_amount) || (totalWithVat - sumLineNet); // IBT-110
  const totalWithoutVat = totalWithVat - totalVat; // IBT-109

  const precedingInvoiceRef = isCreditNote && invoice.related_invoice_number
    ? '  <cac:BillingReference>\n' +
      '    <cac:InvoiceDocumentReference>\n' +
      '      <cbc:ID>' + pintAeXmlEscape(invoice.related_invoice_number) + '</cbc:ID>\n' + // IBT-025
      '    </cac:InvoiceDocumentReference>\n' +
      '  </cac:BillingReference>\n'
    : '';

  const rootTag = isCreditNote ? 'CreditNote' : 'Invoice';
  const nsRoot = isCreditNote
    ? 'urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2'
    : 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2';

  return (
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<' + rootTag + ' xmlns="' + nsRoot + '"\n' +
    '  xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"\n' +
    '  xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">\n' +
    '  <cbc:CustomizationID>urn:peppol:pint:billing-1@ae-1</cbc:CustomizationID>\n' + // IBT-024
    '  <cbc:ProfileID>urn:peppol:pint:billing-1@ae-1</cbc:ProfileID>\n' + // IBT-023
    '  <cbc:ID>' + pintAeXmlEscape(invoice.invoice_number || '') + '</cbc:ID>\n' + // IBT-001
    '  <cbc:UUID>' + uuid + '</cbc:UUID>\n' + // BTAE-07
    '  <cbc:IssueDate>' + issueDate + '</cbc:IssueDate>\n' + // IBT-002
    '  <cbc:' + (isCreditNote ? 'CreditNoteTypeCode' : 'InvoiceTypeCode') + '>' + invoiceTypeCode + '</cbc:' + (isCreditNote ? 'CreditNoteTypeCode' : 'InvoiceTypeCode') + '>\n' + // IBT-003
    '  <cbc:DocumentCurrencyCode>AED</cbc:DocumentCurrencyCode>\n' + // IBT-005
    precedingInvoiceRef +
    '  <cac:AccountingSupplierParty>\n' +
    '    <cac:Party>\n' +
    '      <cbc:EndpointID' + (sellerEndpoint ? '' : ' schemeID="0235"') + '>' + pintAeXmlEscape(sellerEndpoint || 'PENDING-ASP-ASSIGNMENT') + '</cbc:EndpointID>\n' + // IBT-034
    '      <cac:PartyLegalEntity>\n' +
    '        <cbc:RegistrationName>' + pintAeXmlEscape(sellerLegalName) + '</cbc:RegistrationName>\n' + // IBT-027
    '        <cbc:CompanyID schemeID="' + pintAeXmlEscape(sellerRegIdType) + '">' + pintAeXmlEscape(sellerRegId) + '</cbc:CompanyID>\n' + // IBT-030 / BTAE-15
    '      </cac:PartyLegalEntity>\n' +
    '      <cac:PostalAddress>\n' +
    '        <cbc:StreetName>' + pintAeXmlEscape(store.address || '') + '</cbc:StreetName>\n' + // IBT-035
    (store.emirate_code ? '        <cbc:CountrySubentity>' + pintAeXmlEscape(store.emirate_code) + '</cbc:CountrySubentity>\n' : '') + // IBT-039
    '        <cac:Country><cbc:IdentificationCode>' + pintAeXmlEscape(sellerCountry) + '</cbc:IdentificationCode></cac:Country>\n' + // IBT-040
    '      </cac:PostalAddress>\n' +
    (sellerTrn ? '      <cac:PartyTaxScheme>\n        <cbc:CompanyID>' + pintAeXmlEscape(sellerTrn) + '</cbc:CompanyID>\n        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>\n      </cac:PartyTaxScheme>\n' : '') + // IBT-031
    '    </cac:Party>\n' +
    '  </cac:AccountingSupplierParty>\n' +
    '  <cac:AccountingCustomerParty>\n' +
    '    <cac:Party>\n' +
    '      <cac:PartyLegalEntity>\n' +
    '        <cbc:RegistrationName>' + pintAeXmlEscape(buyerName) + '</cbc:RegistrationName>\n' + // IBT-044
    '      </cac:PartyLegalEntity>\n' +
    (buyerAddress ? '      <cac:PostalAddress>\n        <cbc:StreetName>' + pintAeXmlEscape(buyerAddress) + '</cbc:StreetName>\n        <cac:Country><cbc:IdentificationCode>AE</cbc:IdentificationCode></cac:Country>\n      </cac:PostalAddress>\n' : '') + // IBT-050 / IBT-055
    (buyerTrn ? '      <cac:PartyTaxScheme>\n        <cbc:CompanyID>' + pintAeXmlEscape(buyerTrn) + '</cbc:CompanyID>\n        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>\n      </cac:PartyTaxScheme>\n' : '') + // IBT-048
    '    </cac:Party>\n' +
    '  </cac:AccountingCustomerParty>\n' +
    '  <cac:TaxTotal>\n' +
    '    <cbc:TaxAmount currencyID="AED">' + pintAeNum(totalVat) + '</cbc:TaxAmount>\n' + // IBT-110
    '    <cac:TaxSubtotal>\n' +
    '      <cbc:TaxableAmount currencyID="AED">' + pintAeNum(totalWithoutVat) + '</cbc:TaxableAmount>\n' + // IBT-116
    '      <cbc:TaxAmount currencyID="AED">' + pintAeNum(totalVat) + '</cbc:TaxAmount>\n' + // IBT-117
    '      <cac:TaxCategory>\n' +
    '        <cbc:ID>' + vatCategoryCode + '</cbc:ID>\n' + // IBT-118
    (vatRate > 0 ? '        <cbc:Percent>' + pintAeNum(vatRate) + '</cbc:Percent>\n' : '') + // IBT-119
    '        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>\n' +
    '      </cac:TaxCategory>\n' +
    '    </cac:TaxSubtotal>\n' +
    '  </cac:TaxTotal>\n' +
    '  <cac:LegalMonetaryTotal>\n' +
    '    <cbc:LineExtensionAmount currencyID="AED">' + pintAeNum(sumLineNet) + '</cbc:LineExtensionAmount>\n' + // IBT-106
    '    <cbc:TaxExclusiveAmount currencyID="AED">' + pintAeNum(totalWithoutVat) + '</cbc:TaxExclusiveAmount>\n' + // IBT-109
    '    <cbc:TaxInclusiveAmount currencyID="AED">' + pintAeNum(totalWithVat) + '</cbc:TaxInclusiveAmount>\n' + // IBT-112
    '    <cbc:PayableAmount currencyID="AED">' + pintAeNum(totalWithVat) + '</cbc:PayableAmount>\n' + // IBT-115
    '  </cac:LegalMonetaryTotal>\n' +
    lineXml + '\n' +
    '</' + rootTag + '>\n'
  );
}
