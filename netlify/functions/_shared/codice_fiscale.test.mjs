import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { codiceFiscaleChecksum, isValidCodiceFiscale, normalizeCodiceFiscale } from './codice_fiscale.mjs';

describe('codice fiscale', () => {
  it('accetta un CF con checksum corretto, anche con spazi e minuscole', () => {
    assert.equal(codiceFiscaleChecksum('RSSMRA85T10A562'), 'S');
    assert.equal(isValidCodiceFiscale('RSSMRA85T10A562S'), true);
    assert.equal(isValidCodiceFiscale('rss mra85t10a562s'), true);
    assert.equal(normalizeCodiceFiscale(' rss mra85t10a562s '), 'RSSMRA85T10A562S');
  });

  it('rifiuta checksum, lunghezza e mese impossibili', () => {
    assert.equal(isValidCodiceFiscale('RSSMRA85T10A562A'), false);
    assert.equal(isValidCodiceFiscale('RSSMRA85T10A562'), false);
    assert.equal(isValidCodiceFiscale('RSSMRA85X10A562S'), false);
    assert.equal(isValidCodiceFiscale(''), false);
  });
});
