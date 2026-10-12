import unittest
from current_bundle_readiness import is_supporting_reference, unique_refs


class ReferenceRoleTests(unittest.TestCase):
    def test_replacement_provenance_does_not_hide_selected_or_runtime_frame(self):
        entry = {
            'selectedPNG': 'GeneratedCandidates/new.png',
            'supersedesCandidate': {'selectedPNG': 'GeneratedCandidates/old.png'},
            'frameRegistrationCandidate': {'rows': [{
                'sourcePath': 'native/GeneratedArt/party_rest/AIRA.png',
                'runtimeBodyAssetID': 'GeneratedArt/PartyRest/AIRA.png',
            }]},
        }
        references = list(unique_refs(entry))
        runtime = [path for field, path in references if not is_supporting_reference(field, path)]
        self.assertEqual(runtime, ['GeneratedCandidates/new.png', 'GeneratedArt/PartyRest/AIRA.png'])
        self.assertEqual(len(references), 4)

    def test_selected_historical_review_filename_is_still_required(self):
        self.assertFalse(is_supporting_reference('selectedPNG', 'AreaPreview/review.png'))
        self.assertFalse(is_supporting_reference('sceneLayers[0].path', 'AreaPreview/review.png'))


if __name__ == '__main__':
    unittest.main()
