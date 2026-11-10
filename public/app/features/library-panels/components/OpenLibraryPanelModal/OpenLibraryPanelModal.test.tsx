import { render, screen } from 'test/test-utils';

import * as api from '../../state/api';
import { type LibraryElementConnectionDTO, type LibraryElementDTO } from '../../types';

import { OpenLibraryPanelModal } from './OpenLibraryPanelModal';

const libraryPanel: LibraryElementDTO = {
  uid: 'library-panel-uid',
  name: 'Library panel',
  type: 'timeseries',
  version: 1,
  model: { type: 'timeseries', title: 'Library panel' },
};

function getConnections(count: number): LibraryElementConnectionDTO[] {
  return Array.from({ length: count }, (_, index) => ({
    id: index + 1,
    kind: 1,
    elementId: 1,
    connectionId: index + 1,
    connectionUid: `dashboard-uid-${index + 1}`,
    created: '2026-01-01T00:00:00Z',
    createdBy: { id: 1, name: 'admin', avatarUrl: '' },
  }));
}

const getLibraryPanelConnectedDashboardsSpy = jest.spyOn(api, 'getLibraryPanelConnectedDashboards');
jest.spyOn(api, 'getConnectedDashboards').mockResolvedValue([]);

describe('OpenLibraryPanelModal', () => {
  it.each([
    {
      connected: 1,
      expected: 'This panel is being used in 1 dashboard. Please choose which dashboard to view the panel in:',
    },
    {
      connected: 2,
      expected: 'This panel is being used in 2 dashboards. Please choose which dashboard to view the panel in:',
    },
  ])('shows "$expected" when the panel is connected to $connected dashboard(s)', async ({ connected, expected }) => {
    getLibraryPanelConnectedDashboardsSpy.mockResolvedValue(getConnections(connected));

    render(<OpenLibraryPanelModal libraryPanel={libraryPanel} onDismiss={jest.fn()} />);

    expect(await screen.findByText(expected)).toBeInTheDocument();
  });
});
