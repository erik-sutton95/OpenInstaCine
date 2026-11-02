// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Local preview is the site root. opencapture.org serves the handbook under
// /openinstacine/docs/: set HANDBOOK_BASE=/openinstacine/docs for that build.
const handbookBase = process.env.HANDBOOK_BASE || '/';

export default defineConfig({
  site: 'https://opencapture.org',
  base: handbookBase,
  trailingSlash: 'always',
  integrations: [
    starlight({
      title: 'OpenInstaCine',
      description:
        'OpenInstaCine docs: Insta360 Luna Ultra protocol, iOS and Android apps, and how to build.',
      logo: {
        src: './src/assets/icon.png',
        alt: 'OpenInstaCine',
      },
      favicon: 'favicon.png',
      customCss: ['./src/styles/custom.css'],
      editLink: {
        baseUrl: 'https://github.com/erik-sutton95/OpenInstaCine/edit/main/handbook/',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/erik-sutton95/OpenInstaCine',
        },
      ],
      sidebar: [
        {
          label: 'Getting started',
          items: [
            { label: 'Overview', slug: '' },
            { label: 'Setup and build', slug: 'guides/setup' },
            { label: 'Troubleshooting', slug: 'guides/troubleshooting' },
          ],
        },
        {
          label: 'Apps',
          items: [
            { label: 'iOS', slug: 'apps/ios' },
            { label: 'Android', slug: 'apps/android' },
          ],
        },
        {
          label: 'Insta360 Devices',
          items: [
            { label: 'Device references', slug: 'devices' },
            {
              label: 'Luna Ultra', collapsed: true,
              items: [
                { label: 'Overview and evidence', slug: 'devices/luna-ultra' },
                { label: 'Command comparison', slug: 'devices/luna-ultra/commands' },
                { label: 'Shooting modes and formats', slug: 'devices/luna-ultra/modes' },
                { label: 'Exposure, focus and audio', slug: 'devices/luna-ultra/settings' },
                { label: 'Zoom and gimbal controls', slug: 'devices/luna-ultra/controls' },
                { label: 'Original media', slug: 'devices/luna-ultra/media' },
                { label: 'Connection and reconnect', slug: 'devices/luna-ultra/connection' },
                { label: 'Coverage and implementation', slug: 'devices/luna-ultra/coverage' },
              ],
            },
          ],
        },
        {
          label: 'Shared protocol',
          items: [
            { label: 'Connection spine', slug: 'protocol/connection' },
            { label: 'BLE pairing', slug: 'protocol/ble' },
            { label: 'Camera Wi-Fi', slug: 'protocol/wifi' },
            { label: 'UCD2 frame', slug: 'protocol/ucd2-frame' },
            { label: 'UCD2 transport', slug: 'protocol/ucd2-transport' },
            { label: 'Command catalog', slug: 'protocol/commands' },
            { label: 'Live view', slug: 'protocol/live-view' },
            { label: 'Media', slug: 'protocol/media' },
            { label: 'iOS notes', slug: 'protocol/ios' },
          ],
        },
        {
          label: 'Development',
          items: [
            { label: 'Architecture', slug: 'apps/architecture' },
            { label: 'Keeping docs current', slug: 'contribute/documentation' },
          ],
        },
        {
          label: 'Release notes',
          items: [
            { label: '0.1.3', slug: 'releases/0-1-3' },
            { label: 'Open beta 0.1.0', slug: 'releases/0-1-0' },
          ],
        },
      ],
    }),
  ],
});
