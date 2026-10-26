// The script of the page a password setup link opens (ADR-0243); tools/tests/test_setup_page.sh runs it.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { TEXT, appLink, language } = require('./setup.js');

test('hands the app the link with the address of the server it came from', () => {
  assert.equal(
    appLink('https://photos.example.org/photolib/#/password-setup?handle=ann&token=ab12'),
    // What app/test/features/password_setup_link_test.dart opens.
    'photolib:/password-setup?handle=ann&token=ab12&server=https%3A%2F%2Fphotos.example.org%2Fphotolib%2F',
  );
  const lan = new URL(appLink('http://photos.example.org:8080/?x=1#/password-setup?handle=bo&token=cd'));
  assert.equal(lan.searchParams.get('server'), 'http://photos.example.org:8080/');
  for (const page of [
    'https://photos.example.org/',
    'https://photos.example.org/#/password-setup?handle=ann',
    'https://photos.example.org/#/password-setup?token=ab12',
    'https://photos.example.org/#/library?handle=ann&token=ab12',
  ]) {
    assert.equal(appLink(page), null, page);
  }
});

test('speaks every language the apps launch in, with their words for Settings and Add a server', () => {
  const l10n = path.join(__dirname, '../../../../../app/lib/l10n');
  const locales = fs
    .readdirSync(l10n)
    .flatMap((file) => /^app_(.+)\.arb$/.exec(file)?.[1] ?? [])
    .filter((locale) => !['en_XA', 'ar_XB'].includes(locale));
  assert.deepEqual(Object.keys(TEXT).sort(), locales.map((locale) => locale.replace('_', '-')).sort());
  for (const locale of locales) {
    const arb = JSON.parse(fs.readFileSync(path.join(l10n, `app_${locale}.arb`), 'utf8'));
    const [open, paste] = TEXT[locale.replace('_', '-')];
    assert.match(open, /Photolib/, locale);
    for (const words of [arb.settingsTitle, arb.serverAdd]) assert.ok(paste.includes(words), `${locale}: ${words}`);
  }
});

test('picks the first language it speaks, Chinese by script or region, else English', () => {
  for (const [tags, code] of [
    [['xx', 'de-AT', 'fr'], 'de'],
    [['zh-TW'], 'zh-Hant'],
    [['zh-Hant-HK'], 'zh-Hant'],
    [['zh-CN'], 'zh'],
    [['pt-PT'], 'pt'],
    [['XX'], 'en'],
    [[], 'en'],
  ]) {
    assert.equal(language(tags), code, tags.join());
  }
});
