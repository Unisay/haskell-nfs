{-# LANGUAGE OverloadedStrings #-}
module Network.WebDAV.NFS.Response
  ( result
  , emptyResponse
  , statusResponse
  , exceptionResponse
  , xmlResponse
  , errorResponse
  , DAVError(..)
  , davErrorStatus
  , davErrorElements
  , throwDAVError
  , handleDAVError
  , handleNFSException
  ) where

import           Control.Exception (Exception, displayException, throwIO, handle)
import qualified Data.ByteString.Lazy.Char8 as BSLC
import qualified Data.Conduit as C
import           Data.Typeable (Typeable)
import qualified Network.HTTP.Types as HTTP
import qualified Network.NFS.V4 as NFS
import qualified Network.Wai as Wai
import qualified Network.Wai.Conduit as WaiC
import           Waimwork.Result (result)

import           Network.WebDAV.XML
import           Network.WebDAV.DAV

exceptionResponse :: Exception e => HTTP.Status -> e -> Wai.Response
exceptionResponse s = Wai.responseLBS s [(HTTP.hContentType, "text/plain")]
  . BSLC.pack . displayException

emptyResponse :: HTTP.Status -> HTTP.ResponseHeaders -> Wai.Response
emptyResponse s h = Wai.responseLBS s h mempty

statusResponse :: HTTP.Status -> Wai.Response
statusResponse s = emptyResponse s []

xmlResponse :: XML a => HTTP.Status -> HTTP.ResponseHeaders -> a -> Wai.Response
xmlResponse s h x = WaiC.responseSource s h $ C.mapOutput C.Chunk $ xmlRender x

errorResponse :: ErrorElement -> Wai.Response
errorResponse e = xmlResponse (errorElementStatus e) [] e

data DAVError
  = DAVError ErrorElement
  | DAVStatus HTTP.Status
  deriving (Typeable, Show)

instance Exception DAVError

davErrorStatus :: DAVError -> HTTP.Status
davErrorStatus (DAVError e) = errorElementStatus e
davErrorStatus (DAVStatus s) = s

davErrorElements :: DAVError -> Error
davErrorElements (DAVError e) = [Right e]
davErrorElements (DAVStatus _) = []

davErrorResponse :: DAVError -> Wai.Response
davErrorResponse (DAVError e) = errorResponse e
davErrorResponse (DAVStatus s) = statusResponse s

throwDAVError :: DAVError -> IO a
throwDAVError = throwIO

handleDAVError :: IO a -> IO a
handleDAVError = handle $ result . davErrorResponse

nfsErrorStatus :: NFS.Nfsstat4 -> HTTP.Status
nfsErrorStatus NFS.NFS4_OK = HTTP.ok200
nfsErrorStatus NFS.NFS4ERR_PERM = HTTP.forbidden403
nfsErrorStatus NFS.NFS4ERR_ACCESS = HTTP.forbidden403
nfsErrorStatus NFS.NFS4ERR_NOENT = HTTP.notFound404
nfsErrorStatus NFS.NFS4ERR_NOTDIR = HTTP.notFound404
nfsErrorStatus NFS.NFS4ERR_EXIST = HTTP.preconditionFailed412 -- for COPY without overwrite
nfsErrorStatus NFS.NFS4ERR_NAMETOOLONG = HTTP.requestURITooLong414
nfsErrorStatus NFS.NFS4ERR_LOCKED = locked423
nfsErrorStatus NFS.NFS4ERR_NOSPC = insufficientStorage507
nfsErrorStatus NFS.NFS4ERR_DQUOT = insufficientStorage507
nfsErrorStatus _ = HTTP.internalServerError500

handleNFSException :: IO a -> IO a
handleNFSException = handle $ throwDAVError . DAVStatus . maybe HTTP.internalServerError500 nfsErrorStatus . NFS.nfsExceptionStatus
